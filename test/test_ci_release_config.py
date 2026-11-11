"""Validate release scope derivation using fixtures; no AWS calls."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_release_config', ROOT / 'scripts/export-ci-release-config.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
PREFIX = 'arn:aws:ecs:eu-north-1:447558491229:'


class ReleaseConfigTests(unittest.TestCase):
    def setUp(self):
        self.outputs = dict(ecs_cluster_name='mod9-ecs-cluster', ecs_service_name='mod9-ecs-service',
                            task_execution_role_arn='arn:aws:iam::447558491229:role/demo-execution',
                            bootstrap_task_definition_arn=PREFIX + 'task-definition/mod9-ecs-app:1',
                            load_balancer_dns_name='demo.eu-north-1.elb.amazonaws.com',
                            log_group_name='/ecs/mod9-ecs')
        self.service = dict(status='ACTIVE', clusterArn=PREFIX + 'cluster/mod9-ecs-cluster',
                            serviceArn=PREFIX + 'service/mod9-ecs-cluster/mod9-ecs-service',
                            taskDefinition=PREFIX + 'task-definition/mod9-ecs-app:2')

    def test_limits_registration_to_one_family_and_preserves_current_service(self):
        tfvars, ansible = module.derive(self.outputs, self.service, module.ACCOUNT)
        scope = tfvars['ecs_release']
        self.assertEqual(scope['service_arn'], self.service['serviceArn'])
        self.assertEqual(scope['task_definition_arn_pattern'], PREFIX + 'task-definition/mod9-ecs-app:*')
        env = ansible['ci_release_environment']
        self.assertEqual(env['ECS_FAMILY'], 'mod9-ecs-app')
        self.assertEqual(env['APP_HEALTH_URL'], 'http://demo.eu-north-1.elb.amazonaws.com/health')

    def test_rejects_another_account(self):
        with self.assertRaises(ValueError):
            module.derive(self.outputs, self.service, '123456789012')

    def test_rejects_another_execution_role_account(self):
        self.outputs['task_execution_role_arn'] = 'arn:aws:iam::123456789012:role/foreign'
        with self.assertRaises(ValueError):
            module.derive(self.outputs, self.service, module.ACCOUNT)

    def test_rejects_changed_service_identity(self):
        self.service['serviceArn'] = PREFIX + 'service/mod9-ecs-cluster/other-service'
        with self.assertRaises(ValueError):
            module.derive(self.outputs, self.service, module.ACCOUNT)

    def test_rejects_another_task_family(self):
        self.service['taskDefinition'] = PREFIX + 'task-definition/other-family:1'
        with self.assertRaises(ValueError):
            module.derive(self.outputs, self.service, module.ACCOUNT)

    def test_rejects_inactive_service(self):
        self.service['status'] = 'DRAINING'
        with self.assertRaises(ValueError):
            module.derive(self.outputs, self.service, module.ACCOUNT)

    def test_rejects_unexpected_health_endpoint(self):
        self.outputs['load_balancer_dns_name'] = 'unapproved.example'
        with self.assertRaises(ValueError):
            module.derive(self.outputs, self.service, module.ACCOUNT)


if __name__ == '__main__':
    unittest.main()
