"""Exercise rebuild order and interruption handling without AWS or Jenkins."""
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('lab', ROOT / 'scripts/lab.py')
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)
IMAGE = '447558491229.dkr.ecr.eu-north-1.amazonaws.com/mod9-ecs@sha256:' + 'a' * 64
COMMIT = 'b' * 40
REVISION = 'arn:aws:ecs:eu-north-1:447558491229:task-definition/mod9-ecs-app:2'


class FakeLab(lab.Lab):
    def __init__(self, config):
        super().__init__(config, yes=True)
        self.commit = COMMIT
        self.events = []
        self.fail_publish = False
        self.queued = 0
        self.ci_id = 'i-first'

    def tf(self, stack, variables):
        self.events.append(('tf', stack, dict(variables)))
        if stack == 'ci':
            return {'instance_id': self.ci_id, 'public_ip': '8.8.4.4'}
        return {'vpc_id': 'vpc-first', 'load_balancer_dns_name': 'demo.elb.amazonaws.com'}

    def inventory(self, ci):
        self.events.append(('inventory', ci))

    def run(self, args, **kwargs):
        # The release export is the only command used directly by up().
        lab.write_json(lab.ROOT / 'infra/ci/ecs-release.auto.tfvars.json', {'ecs_release': {'service_arn': 'scoped'}})
        lab.write_json(lab.ROOT / 'ansible/inventory/ci-release.yml', {'ci_release_environment': {'ECS_SERVICE': 'mod9-ecs-service'}})

    def ansible(self, playbook, extra=None):
        self.events.append(('ansible', playbook, extra))
        if playbook != 'run_ci_validation.yml':
            return
        record = Path(extra['ci_run_record_path'])
        if not extra.get('ci_resume_validation') and 'ci_resume_queue_id' not in extra:
            self.queued += 1
        if self.fail_publish and not extra['ci_release_approved']:
            lab.write_json(record, {'queue_id': '42', 'source_commit': COMMIT})
            raise lab.LabError('simulated disconnect after queueing')
        lab.write_json(record, {'build_number': 2 if extra['ci_release_approved'] else 1,
                               'source_commit': COMMIT, 'image_digest': IMAGE,
                               'task_definition_arn': REVISION, 'result': 'SUCCESS'})

    def verify_image(self, image):
        self.events.append(('verify-image', image))

    def verify_service(self, *args):
        self.events.append(('verify-service', args))


class LabTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.root_patch = patch.object(lab, 'ROOT', self.root)
        self.work_patch = patch.object(lab, 'WORK', self.root / 'build-metadata/lab')
        self.root_patch.start()
        self.work_patch.start()
        key = self.root / 'key'
        vault = self.root / 'vault'
        password = self.root / 'vault-password'
        for p, content in [(key, 'private-key-fixture'), (key.with_suffix('.pub'), 'ssh-ed25519 fixture'),
                           (vault, '$ANSIBLE_VAULT;1.1;AES256\nfixture'), (password, 'fixture')]:
            p.write_text(content)
            p.chmod(0o600)
        self.config = dict(owner='tester', profile='training', account=lab.ACCOUNT, region=lab.REGION,
                           admin_cidr='8.8.8.8/32', allowed_http_cidrs=['8.8.8.8/32'],
                           ssh_private_key=str(key), vault_file=str(vault), vault_password_file=str(password))

    def tearDown(self):
        self.root_patch.stop()
        self.work_patch.stop()
        self.tmp.cleanup()

    def test_fresh_rebuild_orders_publish_bootstrap_scope_release(self):
        runner = FakeLab(self.config)
        runner.up()
        events = runner.events
        publish = next(i for i,e in enumerate(events) if e[:2] == ('ansible', 'run_ci_validation.yml') and not e[2]['ci_release_approved'])
        baseline = next(i for i,e in enumerate(events) if e[:2] == ('tf', 'ecs-ec2') and e[2]['release_image'] == IMAGE)
        release = next(i for i,e in enumerate(events) if e[:2] == ('ansible', 'run_ci_validation.yml') and e[2]['ci_release_approved'])
        self.assertLess(publish, baseline)
        self.assertLess(baseline, release)
        self.assertEqual(runner.state['phase'], 'complete')
        self.assertEqual(runner.queued, 2)
        ecs = [e[2] for e in events if e[:2] == ('tf', 'ecs-ec2')]
        self.assertIsNone(ecs[0]['release_image'])
        self.assertIn('8.8.4.4/32', ecs[0]['allowed_http_cidrs'])
        self.assertEqual(events[-1][0], 'verify-service')

    def test_completed_up_rechecks_infrastructure_and_health_without_new_builds(self):
        runner = FakeLab(self.config)
        runner.up()
        runner.events.clear()
        runner.up()
        self.assertEqual(runner.queued, 2)
        self.assertFalse(any(e[0] == 'ansible' for e in runner.events))
        self.assertTrue(any(e[:2] == ('tf', 'ci') for e in runner.events))
        self.assertEqual(runner.events[-1][0], 'verify-service')

    def test_disconnect_resumes_exact_queue_and_does_not_queue_another_publish(self):
        runner = FakeLab(self.config)
        runner.fail_publish = True
        with self.assertRaises(lab.LabError):
            runner.up()
        self.assertEqual(runner.queued, 1)
        runner.fail_publish = False
        runner.events.clear()
        runner.up()
        build = next(e for e in runner.events if e[:2] == ('ansible', 'run_ci_validation.yml'))
        self.assertEqual(build[2]['ci_resume_queue_id'], '42')
        self.assertEqual(runner.queued, 2)  # One publish and one release in total.

    def test_interrupted_scope_apply_preserves_release_permissions_on_resume(self):
        runner = FakeLab(self.config)
        original_tf = runner.tf
        def interrupted_tf(stack, variables):
            if stack == 'ci' and variables.get('ecs_release'):
                raise lab.LabError('simulated interruption applying release IAM')
            return original_tf(stack, variables)
        runner.tf = interrupted_tf
        with self.assertRaises(lab.LabError):
            runner.up()
        self.assertTrue(runner.state['release_scope_generated'])
        runner.tf = original_tf
        runner.events.clear()
        runner.up()
        first_ci = next(e for e in runner.events if e[:2] == ('tf','ci'))
        self.assertEqual(first_ci[2]['ecs_release'], {'service_arn':'scoped'})
        self.assertEqual(runner.queued,2)

    def test_missing_submission_id_refuses_to_queue_again(self):
        runner = FakeLab(self.config)
        runner.fail_publish = True
        with self.assertRaises(lab.LabError):
            runner.up()
        (lab.WORK / 'publish.json').unlink()
        runner.fail_publish = False
        with self.assertRaisesRegex(lab.LabError, 'no saved ID'):
            runner.up()
        self.assertEqual(runner.queued, 1)

    def test_explicit_recovery_uses_one_exact_build_only(self):
        runner = FakeLab(self.config)
        runner.fail_publish = True
        with self.assertRaises(lab.LabError):
            runner.up()
        (lab.WORK / 'publish.json').unlink()
        runner.fail_publish = False
        runner.events.clear()
        runner.up(recover=9)
        builds = [e[2] for e in runner.events if e[:2] == ('ansible', 'run_ci_validation.yml')]
        self.assertEqual(builds[0]['ci_resume_build_number'], 9)
        self.assertNotIn('ci_resume_build_number', builds[1])

    def test_changed_source_requires_new_run(self):
        runner = FakeLab(self.config)
        runner.initialize(False)
        runner.commit = 'c' * 40
        with self.assertRaisesRegex(lab.LabError, 'Source/configuration changed'):
            runner.initialize(False)

    def test_changed_instance_does_not_reuse_provisioning_checkpoints(self):
        runner = FakeLab(self.config)
        runner.up()
        runner.ci_id = 'i-replaced'
        with self.assertRaisesRegex(lab.LabError, 'CI instance changed'):
            runner.up()

    def test_restart_archives_build_records_and_clears_bootstrap_image(self):
        runner = FakeLab(self.config)
        runner.up()
        runner.initialize(True)
        self.assertIsNone(runner.state['bootstrap_image'])
        self.assertEqual(runner.state['completed'], [])
        self.assertFalse((lab.WORK / 'release.json').exists())
        self.assertEqual(len(list(lab.WORK.glob('previous-*/release.json'))), 1)

    def test_plans_reject_deletion_and_both_replacement_orders(self):
        for actions in [['delete'], ['delete','create'], ['create','delete']]:
            with self.subTest(actions=actions), self.assertRaises(lab.LabError):
                lab.reject_deletions({'resource_changes': [{'address':'aws_ecs_service.app', 'change':{'actions':actions}}]})
        lab.reject_deletions({'resource_changes':[{'address':'new', 'change':{'actions':['create']}}]})

    def test_checkpoint_is_private_and_parseable(self):
        path = self.root / 'checkpoint.json'
        lab.write_json(path, {'phase':'publish'})
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(path.read_text()), {'phase':'publish'})

    def test_destructive_plan_never_reaches_apply(self):
        runner = lab.Lab(self.config,yes=True)
        calls = []
        def command(args, **kwargs):
            calls.append(args)
            if args[2] == 'workspace':
                return 'default'
            if args[2] == 'plan':
                Path(next(a.removeprefix('-out=') for a in args if isinstance(a,str) and a.startswith('-out='))).touch()
            if args[2] == 'show':
                return json.dumps({'resource_changes':[{'address':'service','change':{'actions':['delete','create']}}]})
            return ''
        runner.run = command
        with self.assertRaises(lab.LabError):
            runner.tf('ci',{})
        self.assertFalse(any(args[2] == 'apply' for args in calls))

    def test_final_health_checks_exact_revision_tasks_targets_and_endpoint(self):
        runner = lab.Lab(self.config)
        service = dict(status='ACTIVE',taskDefinition=REVISION,desiredCount=1,runningCount=1,pendingCount=0,
                       deployments=[{'rolloutState':'COMPLETED'}],
                       loadBalancers=[{'containerName':'app','containerPort':3000,'targetGroupArn':'tg'}])
        task = dict(taskDefinitionArn=REVISION,healthStatus='HEALTHY',lastStatus='RUNNING',
                    containers=[{'name':'app','imageDigest':IMAGE.split('@')[1]}],
                    attachments=[{'type':'ElasticNetworkInterface','details':[{'name':'privateIPv4Address','value':'10.90.1.42'}]}])
        targets = [{'Target':{'Id':'10.90.1.42','Port':3000},'TargetHealth':{'State':'healthy'}}]
        responses = {
            ('ecr','describe-images'):{},
            ('ecs','describe-services'):{'services':[service],'failures':[]},
            ('ecs','describe-task-definition'):{'taskDefinition':{'containerDefinitions':[{'name':'app','image':IMAGE}]}},
            ('ecs','list-tasks'):{'taskArns':['task']},
            ('ecs','describe-tasks'):{'tasks':[task],'failures':[]},
            ('elbv2','describe-target-health'):{'TargetHealthDescriptions':targets},
        }
        runner.aws = lambda *args: responses[args[:2]]
        outputs = dict(ecs_cluster_name='cluster',ecs_service_name='service',load_balancer_dns_name='demo.elb.amazonaws.com')
        with patch.object(lab.urllib.request,'urlopen',return_value=io.BytesIO(b'{"service":"jenkins-webapp","status":"ok"}')):
            runner.verify_service(outputs,IMAGE,REVISION)
        with self.assertRaisesRegex(lab.LabError,'revision differs'):
            runner.verify_service(outputs,IMAGE,REVISION+'0')
        targets[0]['TargetHealth']['State'] = 'unhealthy'
        with self.assertRaisesRegex(lab.LabError,'healthy ALB targets'):
            runner.verify_service(outputs,IMAGE,REVISION)

    def test_concurrent_runs_are_rejected(self):
        path = self.root / 'run.lock'
        with lab.locked(path):
            with self.assertRaises(lab.LabError):
                with lab.locked(path):
                    self.fail('second lock acquired')

    def test_resume_rejects_wrong_source_and_ambiguous_submission(self):
        for record in [{}, {'source_commit':COMMIT}, {'source_commit':'other','build_number':1}]:
            with self.assertRaises(lab.LabError):
                lab.resume_arguments(record, COMMIT)
        self.assertEqual(lab.resume_arguments({'source_commit':COMMIT,'build_number':7},COMMIT),
                         {'ci_resume_validation':True,'ci_resume_build_number':7})

    def test_ssh_requires_fingerprint_from_trusted_console(self):
        import base64
        console = '256 SHA256:trustedkey host (ED25519)'
        self.assertEqual(lab.verified_host_keys('host ssh-ed25519 fixture', console, 'SHA256:trustedkey'),
                         'host ssh-ed25519 fixture')
        lab.verified_host_keys('host ssh-ed25519 fixture',base64.b64encode(console.encode()).decode(),'SHA256:trustedkey')
        with self.assertRaises(lab.LabError):
            lab.verified_host_keys('host ssh-ed25519 fixture',console,'SHA256:attacker')

    def test_configuration_rejects_wrong_account_public_secrets_and_example_cidrs(self):
        path = self.root / 'config.json'
        for override in [dict(account='123456789012'), dict(admin_cidr='203.0.113.10/32'),
                         dict(allowed_http_cidrs=['0.0.0.0/0'])]:
            path.write_text(json.dumps(dict(self.config, **override)))
            with self.assertRaises(lab.LabError):
                lab.load_config(path)
        path.write_text(json.dumps(self.config))
        self.assertEqual(lab.load_config(path)['owner'], 'tester')
        Path(self.config['vault_password_file']).chmod(0o644)
        with self.assertRaisesRegex(lab.LabError, 'owner-only'):
            lab.load_config(path)


if __name__ == '__main__':
    unittest.main()
