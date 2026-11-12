#!/usr/bin/env python3
"""Review or execute narrowly scoped cleanup of the two failed rollback demos."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

REGION = 'eu-north-1'
ACCOUNT = '447558491229'
REPO = 'mod9-ecs'
FAMILY = f'arn:aws:ecs:{REGION}:{ACCOUNT}:task-definition/mod9-ecs-app:'
RETIRED = {FAMILY + '4', FAMILY + '5'}
PREFIX = f'{ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/{REPO}@'


def aws(profile, *args):
    result = subprocess.run(['aws', '--profile', profile, '--region', REGION,
                             *args, '--output', 'json', '--cli-connect-timeout', '10',
                             '--cli-read-timeout', '30'], check=True,
                            capture_output=True, text=True, timeout=90)
    return json.loads(result.stdout)


def select(definitions, references, images):
    """Only known deliberately broken demos, with no remaining consumers."""
    by_arn = {d['taskDefinitionArn']: d for d in definitions}
    if not RETIRED <= by_arn.keys():
        raise ValueError('Both demo revisions must still be ACTIVE for this review')
    if RETIRED & set(references):
        raise ValueError('A demo revision is still referenced by a service or task')
    candidates = set()
    for arn in sorted(RETIRED):
        apps = [c for c in by_arn[arn]['containerDefinitions'] if c['name'] == 'app']
        if len(apps) != 1 or apps[0].get('healthCheck', {}).get('command') != ['CMD-SHELL', 'exit 1']:
            raise ValueError('Unexpected demo revision health check')
        image = apps[0]['image']
        if not image.startswith(PREFIX):
            raise ValueError('Expected a digest in this lab ECR repository')
        candidates.add(image[len(PREFIX):])
    protected = set()
    for d in definitions:
        if d['taskDefinitionArn'] in RETIRED:
            continue
        for container in d['containerDefinitions']:
            image = container['image']
            if image.startswith(PREFIX):
                protected.add(image[len(PREFIX):])
            elif image.startswith(PREFIX.split('@')[0] + ':'):
                tag = image.rsplit(':', 1)[1]
                matches = [i['imageDigest'] for i in images if tag in i.get('imageTags', [])]
                if len(matches) != 1:
                    raise ValueError('Cannot resolve a retained task image tag')
                protected.update(matches)
    if candidates & protected:
        raise ValueError('A demo image is referenced by a retained ACTIVE task definition')
    for digest in candidates:
        matches = [i for i in images if i['imageDigest'] == digest]
        if len(matches) != 1 or matches[0].get('imageManifestMediaType') not in (
                'application/vnd.docker.distribution.manifest.v2+json',
                'application/vnd.oci.image.manifest.v1+json'):
            raise ValueError('Missing image or unsupported manifest/index')
    return {'revisions': sorted(RETIRED), 'imageDigests': sorted(candidates),
            'protectedDigests': sorted(protected)}


def snapshot(profile):
    identity = aws(profile, 'sts', 'get-caller-identity')
    if identity['Account'] != ACCOUNT:
        raise ValueError('Wrong AWS account')
    references = set()
    services = []
    # CLI auto-pagination remains enabled for every list operation.
    for cluster in aws(profile, 'ecs', 'list-clusters')['clusterArns']:
        for arn in aws(profile, 'ecs', 'list-services', '--cluster', cluster)['serviceArns']:
            response = aws(profile, 'ecs', 'describe-services', '--cluster', cluster, '--services', arn)
            if response.get('failures'):
                raise ValueError('Could not inspect service')
            service = response['services'][0]
            references.add(service['taskDefinition'])
            references.update(d['taskDefinition'] for d in service['deployments'])
            references.update(t['taskDefinition'] for t in service.get('taskSets', []))
            if service['serviceName'] == 'mod9-ecs-service':
                if not (len(service['deployments']) == 1 and service['deployments'][0].get('rolloutState') == 'COMPLETED'
                        and service['runningCount'] == service['desiredCount'] > 0 and service['pendingCount'] == 0):
                    raise ValueError('Lab service must be stable before cleanup')
                services.append({'arn': arn, 'revision': service['taskDefinition'],
                                 'deployment': service['deployments'][0]['id']})
        for status in ('RUNNING', 'PENDING'):
            for task in aws(profile, 'ecs', 'list-tasks', '--cluster', cluster, '--desired-status', status)['taskArns']:
                response = aws(profile, 'ecs', 'describe-tasks', '--cluster', cluster, '--tasks', task)
                if response.get('failures'):
                    raise ValueError('Could not inspect task')
                references.update(t['taskDefinitionArn'] for t in response['tasks'])
    if len(services) != 1:
        raise ValueError('Expected exactly one stable lab service')
    definitions = [aws(profile, 'ecs', 'describe-task-definition', '--task-definition', arn)['taskDefinition']
                   for arn in aws(profile, 'ecs', 'list-task-definitions', '--status', 'ACTIVE')['taskDefinitionArns']]
    images = aws(profile, 'ecr', 'describe-images', '--repository-name', REPO)['imageDetails']
    plan = select(definitions, references, images)
    plan['services'] = services
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', default='training')
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--review', type=Path, default=Path('build-metadata/demo-cleanup/review.json'))
    args = parser.parse_args()
    plan = snapshot(args.profile)
    if not args.execute:
        args.review.parent.mkdir(parents=True, exist_ok=True)
        args.review.write_text(json.dumps(plan, indent=2) + '\n')
        print(json.dumps(plan, indent=2))
        print(f'Read-only review saved to {args.review}; no changes made.')
        return
    if json.loads(args.review.read_text()) != plan:
        raise ValueError('Inventory changed since review; regenerate and review before executing')
    # The operator pauses releases/scheduled jobs during cleanup. These two
    # intentionally broken definitions are not scheduled or external consumers.
    results = {'before': plan, 'deregistered': [], 'deleted': []}
    result_path = args.review.parent / 'result.json'
    def save():
        result_path.write_text(json.dumps(results, indent=2) + '\n')
    save()
    for arn in plan['revisions']:
        response = aws(args.profile, 'ecs', 'deregister-task-definition', '--task-definition', arn)
        if response['taskDefinition']['status'] != 'INACTIVE':
            raise ValueError('Deregistration not confirmed')
        results['deregistered'].append(arn)
        save()
    # Refresh all references after deregistration, before deleting any image.
    definitions = [aws(args.profile, 'ecs', 'describe-task-definition', '--task-definition', arn)['taskDefinition']
                   for arn in aws(args.profile, 'ecs', 'list-task-definitions', '--status', 'ACTIVE')['taskDefinitionArns']]
    for digest in plan['imageDigests']:
        if any(c['image'].startswith(PREFIX.split('@')[0]) and
               (c['image'] == PREFIX + digest or '@' not in c['image'])
               for d in definitions for c in d['containerDefinitions']):
            raise ValueError('Retained definition references image or an unresolved tag; deletion stopped')
        response = aws(args.profile, 'ecr', 'batch-delete-image', '--repository-name', REPO,
                       '--image-ids', json.dumps([{'imageDigest': digest}]))
        if response.get('failures') or not response.get('imageIds'):
            raise ValueError('Image deletion not confirmed')
        results['deleted'].append(digest)
        save()
    results['status'] = 'CLEANUP_APPLIED; verify service and rollback image health next'
    save()
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f'Cleanup stopped: {exc}', file=sys.stderr)
        sys.exit(1)
