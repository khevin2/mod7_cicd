#!/usr/bin/env python3
"""Rebuild this fixed-scope lab. No cloud mutations unless invoked with `up`."""
import argparse
import base64
from contextlib import contextmanager
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT = '447558491229'
REGION = 'eu-north-1'
BRANCH = 'feature/secure-ecs-ec2'
REPO = 'khevin2/mod7_cicd'
IMAGE_PATTERN = re.compile(r'^447558491229\.dkr\.ecr\.eu-north-1\.amazonaws\.com/mod9-ecs@sha256:[0-9a-f]{64}$')
WORK = ROOT / 'build-metadata/lab'


class LabError(Exception):
    pass


def write_json(path, data):
    """Atomic, owner-only output; retain the previous checkpoint on interruption."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise LabError('Another lab command is running in this checkout.') from None
        yield


def load_config(path):
    config = json.loads(Path(path).read_text())
    fields = {'owner', 'profile', 'account', 'region', 'admin_cidr',
              'allowed_http_cidrs', 'ssh_private_key', 'vault_file', 'vault_password_file'}
    if not isinstance(config, dict) or config.keys() != fields:
        raise LabError('Configuration must contain exactly the fields in lab.example.json.')
    if any(not isinstance(config[k], str) or not config[k].strip() for k in fields - {'allowed_http_cidrs'}):
        raise LabError('Configuration string fields must be nonempty.')
    if config['account'] != ACCOUNT or config['region'] != REGION:
        raise LabError(f'This version supports only account {ACCOUNT}, region {REGION}.')
    if config['owner'] == 'REPLACE_ME':
        raise LabError('Replace the example owner and network values first.')
    cidrs = config['allowed_http_cidrs']
    if not isinstance(cidrs, list) or not cidrs:
        raise LabError('allowed_http_cidrs must be a nonempty list.')
    for value in [config['admin_cidr'], *cidrs]:
        try:
            network = ipaddress.ip_network(value, strict=True)
        except (ValueError, TypeError):
            raise LabError('Supply valid IPv4 network CIDRs.') from None
        if network.version != 4 or network.prefixlen == 0 or not network.is_global:
            raise LabError('Use actual public IPv4 client CIDRs, not example/private/world-open ranges.')
    if ipaddress.ip_network(config['admin_cidr']).prefixlen != 32:
        raise LabError('admin_cidr must be the operator public IPv4 /32.')
    for key in ('ssh_private_key', 'vault_file', 'vault_password_file'):
        config[key] = str((ROOT / Path(config[key]).expanduser()).resolve())
        file = Path(config[key])
        if not file.is_file():
            raise LabError(f'Missing private input: {key}.')
        if file.stat().st_mode & 0o077:
            raise LabError(f'{key} must have owner-only permissions (chmod 600).')
    if not Path(config['ssh_private_key'] + '.pub').is_file():
        raise LabError('The SSH private key needs its matching .pub file.')
    if not Path(config['vault_file']).read_bytes().startswith(b'$ANSIBLE_VAULT;'):
        raise LabError('vault_file must be encrypted with Ansible Vault.')
    return config


def reject_deletions(plan):
    destructive = [r['address'] for r in plan.get('resource_changes', [])
                   if 'delete' in r['change']['actions']]
    if destructive:
        raise LabError('Plan includes deletion/replacement; review separately: ' + ', '.join(destructive))


def resume_arguments(record, commit):
    if record.get('source_commit') != commit:
        raise LabError('Recorded Jenkins build belongs to a different source commit.')
    if isinstance(record.get('build_number'), int) and record['build_number'] > 0:
        return {'ci_resume_validation': True, 'ci_resume_build_number': record['build_number']}
    queue = str(record.get('queue_id', ''))
    if re.fullmatch(r'[0-9]+', queue):
        return {'ci_resume_queue_id': queue}
    raise LabError('Build submission was interrupted before its ID was saved. Inspect Jenkins and use --recover-build NUMBER; a duplicate build will not be queued.')


def verified_host_keys(scanned, console, fingerprint):
    """Require the scanned Ed25519 key's SHA256 fingerprint in trusted EC2 output."""
    if 'SHA256:' not in console:
        try:
            console = base64.b64decode(console, validate=True).decode()
        except (ValueError, UnicodeDecodeError):
            pass
    trusted = set(re.findall(r'SHA256:[A-Za-z0-9+/]+', console))
    if not scanned.strip() or fingerprint not in trusted:
        raise LabError('SSH key fingerprint does not match trusted EC2 console output.')
    return scanned


class Lab:
    def __init__(self, config, yes=False):
        self.config = config
        self.yes = yes
        self.env = dict(os.environ, AWS_PROFILE=config['profile'], AWS_REGION=REGION,
                        AWS_DEFAULT_REGION=REGION, AWS_PAGER='', TF_IN_AUTOMATION='1')
        self.env.setdefault('ANSIBLE_LOCAL_TEMP', str(WORK / 'ansible-tmp'))
        self.state_path = WORK / 'state.json'
        self.state = {}
        self.commit = ''

    def run(self, args, capture=False, timeout=600):
        result = subprocess.run([str(a) for a in args], cwd=ROOT, env=self.env,
                                text=True, stdout=subprocess.PIPE if capture else None,
                                timeout=timeout, check=True)
        return result.stdout.strip() if capture else ''

    def aws(self, *args):
        return json.loads(self.run(['aws', '--profile', self.config['profile'], '--region', REGION,
                                    *args, '--output', 'json', '--cli-connect-timeout', '10',
                                    '--cli-read-timeout', '30'], capture=True, timeout=120))

    def preflight(self):
        for name in ('aws', 'terraform', 'ansible-playbook', 'ansible-vault', 'git',
                     'ssh', 'ssh-keyscan', 'ssh-keygen'):
            if not shutil.which(name):
                raise LabError(f'Missing executable: {name}. Activate the pinned Ansible controller environment.')
        version = self.run(['ansible-playbook', '--version'], capture=True).splitlines()[0]
        if not re.search(r'\[core 2\.21\.2\]', version):
            raise LabError('Activate an Ansible controller with ansible-core==2.21.2 (ansible/requirements-ci.txt).')
        # Environment injection can change Terraform behavior despite reviewed files.
        if any(k.startswith(('TF_CLI_ARGS', 'TF_VAR_', 'TF_WORKSPACE')) for k in os.environ):
            raise LabError('Unset TF_CLI_ARGS*, TF_VAR_* and TF_WORKSPACE before using this orchestrator.')
        if self.run(['git', 'status', '--porcelain'], capture=True):
            raise LabError('Commit the intended source and leave a clean checkout before rebuilding.')
        if self.run(['git', 'branch', '--show-current'], capture=True) != BRANCH:
            raise LabError(f'Check out {BRANCH} first.')
        self.commit = self.run(['git', 'rev-parse', 'HEAD'], capture=True)
        remote = self.run(['git', 'remote', 'get-url', 'origin'], capture=True)
        if remote not in (f'https://github.com/{REPO}.git', f'https://github.com/{REPO}',
                           f'git@github.com:{REPO}.git'):
            raise LabError(f'The managed Jenkins job requires origin {REPO}.')
        published = self.run(['git', 'ls-remote', 'origin', 'refs/heads/' + BRANCH], capture=True)
        if not published or published.split()[0] != self.commit:
            raise LabError(f'Push this commit to {BRANCH}; Jenkins reads the remote branch.')
        if self.aws('sts', 'get-caller-identity')['Account'] != ACCOUNT:
            raise LabError('AWS credentials select the wrong account.')
        with open(os.devnull, 'w') as sink:
            subprocess.run(['ansible-vault', 'view', self.config['vault_file'],
                            '--vault-password-file', self.config['vault_password_file']],
                           cwd=ROOT, env=self.env, stdout=sink, check=True, timeout=30)
        self.run(['ansible-playbook', '-i', 'localhost,', ROOT / 'ansible/playbooks/validate_lab_inputs.yml',
                  '-e', '@' + self.config['vault_file'],
                  '--vault-password-file', self.config['vault_password_file']], timeout=60)
        print('Preflight passed: published source, AWS account, tools and Vault decryption.', flush=True)

    def checkpoint(self):
        write_json(self.state_path, self.state)

    def initialize(self, restart, fresh=False):
        signature = dict(config=self.config, commit=self.commit,
                         vault_hash=hashlib.sha256(Path(self.config['vault_file']).read_bytes()).hexdigest(),
                         key_hash=hashlib.sha256(Path(self.config['ssh_private_key'] + '.pub').read_bytes()).hexdigest())
        fingerprint = hashlib.sha256(json.dumps(signature, sort_keys=True).encode()).hexdigest()
        if self.state_path.exists() and not restart:
            self.state = json.loads(self.state_path.read_text())
            if self.state.get('fingerprint') != fingerprint:
                raise LabError('Source/configuration changed. Review the previous run and use --restart for a new run.')
        else:
            retained = {}
            if self.state_path.exists():
                previous = json.loads(self.state_path.read_text())
                if fresh:
                    self.require_teardown(previous)
                else:
                    # Build/configuration checkpoints may be reset without
                    # removing the infrastructure needed by a later retry.
                    retained = {key: previous[key] for key in (
                        'bootstrap_image', 'ci_instance', 'ecs_vpc', 'release_scope_generated'
                    ) if key in previous}
                archive = WORK / ('previous-' + str(time.time_ns()))
                archive.mkdir(mode=0o700)
                for path in WORK.glob('*.json'):
                    path.replace(archive / path.name)
            self.state = dict(version=1, fingerprint=fingerprint, commit=self.commit,
                              completed=[], bootstrap_image=None)
            self.state.update(retained)
            if self.state['bootstrap_image']:
                self.state['completed'].append('publish')
            self.checkpoint()

    def require_teardown(self, previous):
        if previous.get('ci_instance'):
            instances = self.aws('ec2', 'describe-instances', '--filters',
                                 'Name=instance-id,Values=' + previous['ci_instance'])
            if any(i['State']['Name'] != 'terminated' for r in instances['Reservations'] for i in r['Instances']):
                raise LabError('--fresh requires the previous CI instance to be terminated first.')
        if previous.get('ecs_vpc'):
            networks = self.aws('ec2', 'describe-vpcs', '--filters', 'Name=vpc-id,Values=' + previous['ecs_vpc'])
            if networks['Vpcs']:
                raise LabError('--fresh requires the previous ECS VPC to be deleted first.')

    def tf(self, stack, variables):
        """Always refresh/plan; never trust a cached successful Terraform phase."""
        directory = ROOT / 'infra' / stack
        varfile = WORK / (stack + '-inputs.json')
        write_json(varfile, variables)
        base = ['terraform', '-chdir=' + str(directory)]
        self.run([*base, 'init', '-input=false', '-lockfile=readonly'], timeout=600)
        if self.run([*base, 'workspace', 'show'], capture=True) != 'default':
            raise LabError('Only the default Terraform workspace is supported.')
        self.run([*base, 'validate', '-no-color'])
        planfile = WORK / (stack + '.tfplan')
        self.run([*base, 'plan', '-input=false', '-lock-timeout=60s',
                  '-var-file=' + str(varfile), '-out=' + str(planfile)], timeout=1800)
        os.chmod(planfile, 0o600)
        plan = json.loads(self.run([*base, 'show', '-json', planfile], capture=True))
        reject_deletions(plan)
        changes = (any(r['change']['actions'] != ['no-op'] for r in plan.get('resource_changes', []))
                   or any(v['actions'] != ['no-op'] for v in plan.get('output_changes', {}).values()))
        if changes:
            if not self.yes and input(f'Apply the displayed {stack} plan? [yes/no] ').strip() != 'yes':
                raise LabError('Stopped before apply. Rerun the same command to continue.')
            self.run([*base, 'apply', '-input=false', '-lock-timeout=60s', planfile], timeout=3600)
        outputs = json.loads(self.run([*base, 'output', '-json'], capture=True))
        return {name: entry['value'] for name, entry in outputs.items()}

    def ansible(self, playbook, extra=None):
        args = ['ansible-playbook', '-i', ROOT / 'ansible/inventory/ci.yml',
                ROOT / 'ansible/playbooks' / playbook,
                '-e', '@' + self.config['vault_file'],
                '--vault-password-file', self.config['vault_password_file']]
        if playbook == 'configure_ci_demo.yml':
            args += ['-e', '@' + str(ROOT / 'ansible/vars/ci-images.yml')]
        if extra:
            args += ['-e', json.dumps(extra)]
        self.run(args, timeout=7200)

    def step(self, name, action):
        if name in self.state['completed']:
            print(f'Already completed: {name}', flush=True)
            return
        self.state['phase'] = name
        self.checkpoint()
        print(f'Starting: {name}', flush=True)
        action()
        self.state['completed'].append(name)
        self.checkpoint()

    def inventory(self, ci):
        ip = str(ipaddress.IPv4Address(ci['public_ip']))
        instance = self.aws('ec2', 'describe-instances', '--instance-ids', ci['instance_id'])['Reservations'][0]['Instances'][0]
        if instance['State']['Name'] != 'running' or instance.get('PublicIpAddress') != ip:
            raise LabError('Terraform CI instance identity/address does not match AWS.')
        hostfile = ROOT / 'ansible/inventory/known_hosts'
        deadline = time.monotonic() + 600
        verified = None
        while time.monotonic() < deadline:
            console = self.aws('ec2', 'get-console-output', '--instance-id', ci['instance_id'], '--latest').get('Output', '')
            scan = subprocess.run(['ssh-keyscan', '-T', '5', '-t', 'ed25519', ip],
                                  capture_output=True, text=True, timeout=20)
            if scan.returncode == 0 and scan.stdout.strip():
                with tempfile.NamedTemporaryFile(mode='w', dir=WORK) as stream:
                    stream.write(scan.stdout)
                    stream.flush()
                    key_info = self.run(['ssh-keygen', '-lf', stream.name, '-E', 'sha256'], capture=True)
                try:
                    verified = verified_host_keys(scan.stdout, console, key_info.split()[1])
                    break
                except LabError:
                    pass  # Console fingerprints may not have appeared yet.
            time.sleep(5)
        if verified is None:
            raise LabError('Timed out verifying SSH host keys through EC2 console output; no key was trusted.')
        # This is the single-host lab's managed trust file, not ~/.ssh/known_hosts.
        hostfile.write_text(verified)
        hostfile.chmod(0o600)
        write_json(ROOT / 'ansible/inventory/ci.yml', {'all': {'children': {'ci_demo': {'hosts': {'mod9_ci': {
            'ansible_host': ip, 'ansible_user': 'ec2-user', 'ansible_python_interpreter': '/usr/bin/python3',
            'ansible_ssh_private_key_file': self.config['ssh_private_key'], 'ansible_timeout': 60,
            'ansible_ssh_pipelining': True, 'ansible_ssh_args': '-C -o ControlMaster=no -o ControlPath=none',
            'ansible_ssh_common_args': '-o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -o ConnectTimeout=10 -o UserKnownHostsFile=' + str(hostfile),
        }}}}}})

    def build(self, name, release, recover=None):
        record_path = WORK / (name + '.json')
        started = name in self.state.setdefault('builds_started', [])
        extra = dict(ci_publish_approved=True, ci_release_approved=release,
                     ci_run_record_path=str(record_path), ci_expected_source_commit=self.commit)
        if recover is not None:
            if not started:
                raise LabError('--recover-build applies only to a previously started build phase.')
            write_json(record_path, {'build_number': recover, 'source_commit': self.commit})
        if started:
            record = json.loads(record_path.read_text()) if record_path.exists() else {}
            if not record:
                raise LabError('Previous build submission has no saved ID. Inspect Jenkins, then use --recover-build NUMBER.')
            extra.update(resume_arguments(record, self.commit))
        else:
            self.state['builds_started'].append(name)
            self.checkpoint()  # A crash around queue submission must never silently requeue.
        self.ansible('run_ci_validation.yml', extra)
        result = json.loads(record_path.read_text())
        if result.get('result') != 'SUCCESS' or not IMAGE_PATTERN.fullmatch(result.get('image_digest', '')):
            raise LabError('Jenkins did not produce a successful, verified image result.')
        if result.get('source_commit') != self.commit:
            raise LabError('Jenkins built a different commit.')
        return result

    def up(self, restart=False, recover=None, fresh=False):
        self.initialize(restart, fresh)
        recovery_phase = self.state.get('phase')
        if recover is not None and recovery_phase not in ('publish', 'release'):
            raise LabError('--recover-build requires an interrupted publish or release phase.')
        ci_vars = dict(owner=self.config['owner'], admin_cidr=self.config['admin_cidr'],
                       ssh_public_key_path=self.config['ssh_private_key'] + '.pub', ecs_release=None)
        # Preserve previously generated release IAM on resumed runs.
        scope_file = ROOT / 'infra/ci/ecs-release.auto.tfvars.json'
        if self.state.get('release_scope_generated'):
            ci_vars.update(json.loads(scope_file.read_text()))
        ci = self.tf('ci', ci_vars)
        if self.state.get('ci_instance') not in (None, ci['instance_id']):
            raise LabError('CI instance changed. After verified teardown, use --restart --fresh.')
        self.state['ci_instance'] = ci['instance_id']
        self.checkpoint()
        self.inventory(ci)
        # Existing playbooks load this optional file; stale ARNs must not leak into bootstrap.
        if not self.state.get('release_scope_generated'):
            write_json(ROOT / 'ansible/inventory/ci-release.yml', {'ci_release_environment': {}})
        self.step('ci-foundation', lambda: self.ansible('configure_ci_demo.yml'))
        self.step('ci-security', lambda: self.ansible('configure_ci_security.yml'))
        ecs_vars = dict(owner=self.config['owner'], aws_region=REGION, project_name='mod9-ecs',
                        allowed_http_cidrs=sorted(set(self.config['allowed_http_cidrs'] + [self.config['admin_cidr'], ci['public_ip'] + '/32'])),
                        release_image=self.state['bootstrap_image'])
        ecs = self.tf('ecs-ec2', ecs_vars)
        if self.state.get('ecs_vpc') not in (None, ecs['vpc_id']):
            raise LabError('ECS VPC changed. After verified teardown, use --restart --fresh.')
        self.state['ecs_vpc'] = ecs['vpc_id']
        self.checkpoint()
        def publish():
            self.state['bootstrap_image'] = self.build('publish', False, recover if recovery_phase == 'publish' else None)['image_digest']
            self.checkpoint()
        self.step('publish', publish)
        ecs_vars['release_image'] = self.state['bootstrap_image']
        self.verify_image(self.state['bootstrap_image'])
        ecs = self.tf('ecs-ec2', ecs_vars)
        def scope():
            self.run([sys.executable, ROOT / 'scripts/export-ci-release-config.py', '--profile', self.config['profile']])
            # Persist intent before apply: an interrupted IAM apply must not
            # make the next invocation plan removal of the new release policy.
            self.state['release_scope_generated'] = True
            self.checkpoint()
            ci_vars.update(json.loads(scope_file.read_text()))
            self.tf('ci', ci_vars)
        self.step('release-scope', scope)
        self.step('release', lambda: self.build('release', True, recover if recovery_phase == 'release' else None))
        # Recheck the deployed release on every up, including a resumed/completed run.
        result = json.loads((WORK / 'release.json').read_text())
        self.verify_service(ecs, result['image_digest'], result['task_definition_arn'])
        self.state['phase'] = 'complete'
        self.checkpoint()
        print('Lab ready: http://' + ecs['load_balancer_dns_name'] + '/health', flush=True)
        print('State and build records: ' + str(WORK), flush=True)

    def verify_image(self, image):
        if not IMAGE_PATTERN.fullmatch(image):
            raise LabError('Invalid lab ECR digest.')
        self.aws('ecr', 'describe-images', '--repository-name', 'mod9-ecs',
                 '--image-ids', 'imageDigest=' + image.split('@')[1])

    def verify_service(self, outputs, image, revision):
        self.verify_image(image)
        response = self.aws('ecs', 'describe-services', '--cluster', outputs['ecs_cluster_name'],
                            '--services', outputs['ecs_service_name'])
        if response.get('failures') or len(response.get('services', [])) != 1:
            raise LabError('Expected one deployed ECS service.')
        service = response['services'][0]
        if service['taskDefinition'] != revision:
            raise LabError('Active service revision differs from the requested Jenkins release.')
        deployments = service['deployments']
        if (service['status'] != 'ACTIVE' or service['desiredCount'] != service['runningCount']
                or service['desiredCount'] < 1 or service['pendingCount'] != 0
                or len(deployments) != 1 or deployments[0].get('rolloutState') != 'COMPLETED'):
            raise LabError('ECS service is not a completed, healthy deployment.')
        definition = self.aws('ecs', 'describe-task-definition', '--task-definition', service['taskDefinition'])['taskDefinition']
        if not any(c['name'] == 'app' and c['image'] == image for c in definition['containerDefinitions']):
            raise LabError('Active service is not running the expected release image.')
        tasks = self.aws('ecs', 'list-tasks', '--cluster', outputs['ecs_cluster_name'],
                         '--service-name', outputs['ecs_service_name'])['taskArns']
        if len(tasks) != service['desiredCount']:
            raise LabError('Unexpected running task count.')
        data = self.aws('ecs', 'describe-tasks', '--cluster', outputs['ecs_cluster_name'], '--tasks', *tasks)
        if data.get('failures') or len(data['tasks']) != len(tasks) or any(
                t['taskDefinitionArn'] != service['taskDefinition'] or t.get('healthStatus') != 'HEALTHY'
                or t.get('lastStatus') != 'RUNNING'
                or not any(c['name'] == 'app' and c.get('imageDigest') == image.split('@')[1]
                           for c in t['containers']) for t in data['tasks']):
            raise LabError('Running task health, revision or digest does not match the release.')
        groups = [g['targetGroupArn'] for g in service['loadBalancers'] if g['containerName'] == 'app' and g['containerPort'] == 3000]
        if len(groups) != 1:
            raise LabError('Expected one application target group.')
        targets = self.aws('elbv2', 'describe-target-health', '--target-group-arn', groups[0])['TargetHealthDescriptions']
        ips = [d['value'] for t in data['tasks'] for a in t['attachments'] if a['type'] == 'ElasticNetworkInterface'
               for d in a['details'] if d['name'] == 'privateIPv4Address']
        if len(ips) != len(tasks) or any(not any(h['Target']['Id'] == ip and h['Target']['Port'] == 3000
                and h['TargetHealth']['State'] == 'healthy' for h in targets) for ip in ips):
            raise LabError('Running tasks do not have matching healthy ALB targets.')
        dns = outputs['load_balancer_dns_name']
        if not re.fullmatch(r'[A-Za-z0-9.-]+\.elb\.amazonaws\.com', dns):
            raise LabError('Unexpected ALB DNS name.')
        with urllib.request.urlopen('http://' + dns + '/health', timeout=10) as health:
            body = json.load(health)
        if body.get('service') != 'jenkins-webapp' or body.get('status') != 'ok':
            raise LabError('Application health endpoint did not return the expected response.')
        write_json(WORK / 'verified-service.json', response)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['check', 'up', 'status'])
    parser.add_argument('--config', default='lab.local.json', help='JSON configuration; paths resolve from the repository root')
    parser.add_argument('--yes', action='store_true', help='Authorize all non-destructive Terraform applies and the Jenkins publish/release builds')
    parser.add_argument('--restart', action='store_true', help='Reset build/configuration checkpoints while preserving infrastructure settings')
    parser.add_argument('--fresh', action='store_true', help='With --restart, discard infrastructure settings after verified teardown')
    parser.add_argument('--recover-build', type=int, help='Exact Jenkins build number to recover an ambiguous interrupted submission')
    args = parser.parse_args(argv)
    if args.recover_build is not None and args.recover_build < 1:
        parser.error('--recover-build must be positive')
    if args.fresh and not args.restart:
        parser.error('--fresh requires --restart')
    if args.command != 'up' and (args.yes or args.restart or args.fresh or args.recover_build is not None):
        parser.error('--yes, --restart, --fresh and --recover-build apply only to up')
    os.umask(0o077)
    try:
        if args.command == 'status':
            path = WORK / 'state.json'
            print(path.read_text() if path.exists() else 'No orchestrator run recorded.')
            return 0
        lab = Lab(load_config(ROOT / args.config), args.yes)
        with locked(WORK / 'run.lock'):
            lab.preflight()
            if args.command == 'up':
                print('Scope: create/configure this lab and publish/deploy security-approved images; no rollback or cleanup demos.', flush=True)
                if not args.yes and input('Authorize this rebuild, image publication and ECS release? [yes/no] ').strip() != 'yes':
                    raise LabError('Rebuild not authorized.')
                lab.up(args.restart, args.recover_build, args.fresh)
        return 0
    except (LabError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f'Lab stopped: {error}', file=sys.stderr)
        print('No automatic teardown was attempted. Inspect status and rerun the same command to resume.', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('\nInterrupted. Check Jenkins/Terraform before resuming; resources were retained.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    sys.exit(main())
