#!/usr/bin/env python3
"""Generate ignored Terraform/Ansible release inputs using read-only AWS calls."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT = '447558491229'
REGION = 'eu-north-1'


def derive(outputs, service, account):
    if account != ACCOUNT:
        raise ValueError('Unexpected AWS account')
    cluster, name = outputs['ecs_cluster_name'], outputs['ecs_service_name']
    if not name or service.get('status') != 'ACTIVE':
        raise ValueError('Bootstrap an active ECS service first')
    prefix = f'arn:aws:ecs:{REGION}:{account}:'
    if service['clusterArn'] != prefix + 'cluster/' + cluster:
        raise ValueError('Cluster identity mismatch')
    if service['serviceArn'] != prefix + 'service/' + cluster + '/' + name:
        raise ValueError('Service identity mismatch')
    execution_role = outputs['task_execution_role_arn']
    if not re.fullmatch(r'arn:aws:iam::' + account + r':role/[A-Za-z0-9+=,.@_/-]+', execution_role):
        raise ValueError('Execution role account mismatch or invalid ARN')
    pattern = re.escape(prefix + 'task-definition/') + r'([A-Za-z0-9_-]+):[0-9]+'
    bootstrap = re.fullmatch(pattern, outputs['bootstrap_task_definition_arn'])
    current = re.fullmatch(pattern, service['taskDefinition'])
    if not bootstrap or not current or bootstrap[1] != current[1]:
        raise ValueError('Task definition family mismatch')
    dns = outputs['load_balancer_dns_name']
    if not re.fullmatch(r'[A-Za-z0-9.-]+\.elb\.amazonaws\.com', dns):
        raise ValueError('Unexpected ALB DNS name')
    scope = dict(cluster_arn=service['clusterArn'], service_arn=service['serviceArn'],
                 task_definition_arn_pattern=prefix + 'task-definition/' + bootstrap[1] + ':*',
                 execution_role_arn=execution_role)
    env = dict(ECS_CLUSTER=cluster, ECS_SERVICE=name, ECS_FAMILY=bootstrap[1],
               TASK_EXECUTION_ROLE_ARN=execution_role, ECS_LOG_GROUP=outputs['log_group_name'],
               APP_HEALTH_URL='http://' + dns + '/health')
    return {'ecs_release': scope}, {'ci_release_environment': env}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', default='training')
    args = parser.parse_args()

    def aws(*arguments):
        return json.loads(subprocess.check_output(
            ['aws', '--profile', args.profile, '--region', REGION, *arguments, '--output', 'json'], text=True))

    raw = json.loads(subprocess.check_output(
        ['terraform', '-chdir=' + str(ROOT / 'infra/ecs-ec2'), 'output', '-json'], text=True))
    outputs = {name: entry['value'] for name, entry in raw.items()}
    if not outputs.get('ecs_service_name'):
        raise ValueError('Bootstrap the ECS service before configuring Jenkins releases')
    result = aws('ecs', 'describe-services', '--cluster', outputs['ecs_cluster_name'],
                 '--services', outputs['ecs_service_name'])
    if result.get('failures') or len(result.get('services', [])) != 1:
        raise ValueError('Expected exactly one existing ECS service')
    tfvars, ansible = derive(outputs, result['services'][0], aws('sts', 'get-caller-identity')['Account'])
    for relative, data in [('infra/ci/ecs-release.auto.tfvars.json', tfvars),
                           ('ansible/inventory/ci-release.yml', ansible)]:
        path = ROOT / relative
        # JSON is also valid YAML; no additional controller dependencies needed.
        temporary = path.with_name(path.name + '.tmp')
        temporary.write_text(json.dumps(data, indent=2) + '\n')
        temporary.chmod(0o600)
        temporary.replace(path)
        print('Generated ignored local configuration: ' + relative)


if __name__ == '__main__':
    main()
