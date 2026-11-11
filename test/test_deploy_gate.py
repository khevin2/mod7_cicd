"""Exercise ECS verification with a fake AWS CLI; no cloud calls are made."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT = '123456789012'
IMAGE = f'{ACCOUNT}.dkr.ecr.eu-north-1.amazonaws.com/mod9-ecs@sha256:' + 'a' * 64
REVISION = f'arn:aws:ecs:eu-north-1:{ACCOUNT}:task-definition/mod9-ecs-app:2'

AWS_FAKE = '''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['FAKE_AWS_LOG'], 'a') as f: f.write(' '.join(args[:2]) + '\\n')
revision, image = os.environ['FAKE_REVISION'], os.environ['FAKE_IMAGE']
if args[:2] == ['sts', 'get-caller-identity']:
    print('123456789012')
elif args[:2] == ['ecs', 'describe-services']:
    before = not os.path.exists('build-metadata/task-definition-arn.txt')
    rollback = not before and os.environ.get('FAKE_ROLLBACK') == '1'
    arn = 'previous' if before or rollback else revision
    state = 'COMPLETED'
    if not before:
        from pathlib import Path
        counter = Path('build-metadata/describe-after-count.txt')
        count = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(count))
        if os.environ.get('FAKE_PROGRESS_THEN_COMPLETE') == '1' and count < 3:
            state = 'IN_PROGRESS'
        if os.environ.get('FAKE_STUCK_PROGRESS') == '1':
            state = 'IN_PROGRESS'
        if os.environ.get('FAKE_FAILED_ROLLOUT') == '1':
            state = 'FAILED'
    print(json.dumps({'failures': [], 'services': [{'status':'ACTIVE', 'taskDefinition':arn,
        'desiredCount':1, 'runningCount':1, 'loadBalancers':[{'containerName':'app','containerPort':3000,'targetGroupArn':'target-group'}], 'deployments':[{'status':'PRIMARY',
        'taskDefinition':arn, 'rolloutState':state}]}]}))
elif args[:2] == ['ecs', 'register-task-definition']:
    print(json.dumps({'taskDefinition': {'taskDefinitionArn':revision,
        'containerDefinitions':[{'name':'app','image':image}]}}))
elif args[:2] == ['ecs', 'update-service']:
    print('{}')
elif args[:2] == ['ecs', 'wait']:
    pass
elif args[:2] == ['ecs', 'list-tasks']:
    print(json.dumps({'taskArns':['task-1']}))
elif args[:2] == ['ecs', 'describe-tasks']:
    digest = 'sha256:' + 'b' * 64 if os.environ.get('FAKE_WRONG_DIGEST') == '1' else image.split('@')[1]
    print(json.dumps({'failures':[], 'tasks':[{'taskDefinitionArn':revision, 'lastStatus':'RUNNING',
        'healthStatus':'HEALTHY', 'attachments':[{'type':'ElasticNetworkInterface','details':[{'name':'privateIPv4Address','value':'10.90.1.42'}]}], 'containers':[{'name':'app','imageDigest':digest}]}]}))
elif args[:2] == ['elbv2', 'describe-target-health']:
    state = 'unhealthy' if os.environ.get('FAKE_UNHEALTHY_TARGET') == '1' else 'healthy'
    print(json.dumps({'TargetHealthDescriptions':[{'Target':{'Id':'10.90.1.42','Port':3000},'TargetHealth':{'State':state}}]}))
else:
    sys.exit('unexpected call ' + repr(args))
'''


class DeployGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for name in ('scripts', 'ecs', 'bin', 'build-metadata'):
            (self.root / name).mkdir()
        for name in ('deploy-ecs.sh', 'render-ecs-task.py'):
            shutil.copy(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        shutil.copy(ROOT / 'ecs/task-definition.json.tftpl', self.root / 'ecs')
        (self.root / 'bin/aws').write_text(AWS_FAKE)
        (self.root / 'bin/aws').chmod(0o755)
        (self.root / 'bin/curl').write_text('#!/bin/sh\nprintf \'{"service":"jenkins-webapp","status":"ok"}\\n\'\n')
        (self.root / 'bin/curl').chmod(0o755)
        (self.root / 'bin/sleep').write_text('#!/bin/sh\nexit 0\n')
        (self.root / 'bin/sleep').chmod(0o755)
        (self.root / 'build-metadata/image-digest.txt').write_text(IMAGE + '\n')
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}", AWS_REGION='eu-north-1',
            AWS_ACCOUNT_ID=ACCOUNT, ECS_CLUSTER='cluster', ECS_SERVICE='service', ECS_FAMILY='mod9-ecs-app',
            TASK_EXECUTION_ROLE_ARN=f'arn:aws:iam::{ACCOUNT}:role/ecs-exec', ECS_LOG_GROUP='/ecs/mod9-ecs',
            APP_HEALTH_URL='http://example.invalid/health', FAKE_AWS_LOG=str(self.root / 'aws.log'),
            FAKE_REVISION=REVISION, FAKE_IMAGE=IMAGE)

    def tearDown(self):
        self.tmp.cleanup()

    def run_deploy(self):
        return subprocess.run(['bash', 'scripts/deploy-ecs.sh'], cwd=self.root, env=self.env,
                              capture_output=True, text=True)

    def test_healthy_requested_revision_passes(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'build-metadata/task-definition-arn.txt').read_text().strip(), REVISION)
        self.assertTrue((self.root / 'build-metadata/health-response.json').exists())

    def test_waiter_success_after_rollback_fails(self):
        self.env['FAKE_ROLLBACK'] = '1'
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('ecs list-tasks', (self.root / 'aws.log').read_text())
        self.assertTrue((self.root / 'build-metadata/service-after.json').exists())

    def test_waiter_returns_before_rollout_completion_then_passes(self):
        self.env['FAKE_PROGRESS_THEN_COMPLETE'] = '1'
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'build-metadata/describe-after-count.txt').read_text(), '3')
        self.assertTrue((self.root / 'build-metadata/health-response.json').exists())

    def test_failed_requested_rollout_blocks_without_waiting(self):
        self.env['FAKE_FAILED_ROLLOUT'] = '1'
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Requested ECS deployment failed', result.stderr)
        self.assertEqual((self.root / 'build-metadata/describe-after-count.txt').read_text(), '1')
        self.assertNotIn('ecs list-tasks', (self.root / 'aws.log').read_text())

    def test_stuck_rollout_times_out_and_blocks(self):
        self.env['FAKE_STUCK_PROGRESS'] = '1'
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Timed out', result.stderr)
        self.assertEqual((self.root / 'build-metadata/describe-after-count.txt').read_text(), '60')
        self.assertNotIn('ecs list-tasks', (self.root / 'aws.log').read_text())

    def test_unexpected_running_digest_fails(self):
        self.env['FAKE_WRONG_DIGEST'] = '1'
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'build-metadata/health-response.json').exists())

    def test_unhealthy_load_balancer_target_fails(self):
        self.env['FAKE_UNHEALTHY_TARGET'] = '1'
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'build-metadata/health-response.json').exists())


class PublishGateTests(unittest.TestCase):
    def test_changed_image_fails_before_aws_or_push(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for directory in ('scripts', 'bin', 'build-metadata'):
                (root / directory).mkdir()
            shutil.copy(ROOT / 'scripts/publish-ecr.sh', root / 'scripts')
            (root / 'build-metadata/scanned-image-id.txt').write_text('sha256:scanned\n')
            (root / 'bin/docker').write_text('#!/bin/sh\nprintf "sha256:changed\\n"\n')
            (root / 'bin/docker').chmod(0o755)
            (root / 'bin/aws').write_text('#!/bin/sh\ntouch aws-was-called\nexit 0\n')
            (root / 'bin/aws').chmod(0o755)
            env = dict(os.environ, PATH=f"{root / 'bin'}:{os.environ['PATH']}", AWS_REGION='eu-north-1',
                       AWS_ACCOUNT_ID=ACCOUNT, ECR_REPOSITORY='mod9-ecs', IMAGE_REF='local:test',
                       GIT_SHA='a' * 40, BUILD_NUMBER='1')
            result = subprocess.run(['bash', 'scripts/publish-ecr.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'aws-was-called').exists())


if __name__ == '__main__':
    unittest.main()
