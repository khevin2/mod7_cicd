"""Test alarm mutation/restoration with a fake API, never AWS."""
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('monitoring_demo', Path(__file__).resolve().parents[1] / 'scripts/exercise-monitoring.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakeApi:
    def __init__(self):
        self.config = dict(AlarmName=module.ALARM, Namespace='AWS/ApplicationELB',
                           MetricName='HealthyHostCount', Statistic='Maximum', Period=60,
                           EvaluationPeriods=3, DatapointsToAlarm=3, Threshold=1,
                           ComparisonOperator='LessThanThreshold', TreatMissingData='breaching',
                           ActionsEnabled=True, AlarmActions=[], OKActions=[], InsufficientDataActions=[],
                           Dimensions=[{'Name':'LoadBalancer','Value':'app/demo/id'},
                                       {'Name':'TargetGroup','Value':'targetgroup/demo/id'}])
        self.puts = []
        self.maximum = 1

    def __call__(self, service, operation, **payload):
        if operation == 'describe-alarms':
            return {'MetricAlarms':[dict(copy.deepcopy(self.config), StateValue='ALARM' if self.config['Threshold']==2 else 'OK')]}
        if operation == 'get-metric-statistics':
            return {'Datapoints':[{'Timestamp':(datetime.now(timezone.utc)-timedelta(seconds=60)).isoformat(), 'Maximum':self.maximum}]}
        if operation == 'put-metric-alarm':
            self.puts.append(copy.deepcopy(payload))
            self.config=copy.deepcopy(payload)
            return {}
        if operation == 'describe-alarm-history':
            return {'AlarmHistoryItems':[]}
        raise AssertionError(operation)


class MonitoringDemoTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.api=FakeApi()

    def test_default_is_read_only(self):
        result=module.exercise(self.api, self.tmp.name)
        self.assertEqual(result['status'],'PREPARED')
        self.assertEqual(self.api.puts,[])

    def test_real_metric_condition_and_exact_restoration(self):
        original=copy.deepcopy(self.api.config)
        result=module.exercise(self.api,self.tmp.name,execute=True)
        self.assertEqual(result['status'],'PASS')
        self.assertTrue(result['alarmObserved'] and result['recoveryObserved'])
        self.assertEqual(self.api.puts,[dict(original,Threshold=2),original])
        self.assertEqual(self.api.config,original)

    def test_timeout_restores_original_and_still_fails(self):
        original=copy.deepcopy(self.api.config)
        with patch.object(module,'wait_for_state',side_effect=[TimeoutError('test timeout'),{'StateValue':'OK'}]):
            with self.assertRaises(TimeoutError):
                module.exercise(self.api,self.tmp.name,execute=True)
        self.assertEqual(self.api.config,original)
        result=json.loads((Path(self.tmp.name)/'monitoring-demo-result.json').read_text())
        self.assertEqual(result['status'],'FAILED')
        self.assertTrue(result['originalConfigurationRestored'])

    def test_notification_actions_block_before_any_mutation(self):
        self.api.config['AlarmActions']=['arn:aws:sns:eu-north-1:447558491229:example']
        with self.assertRaisesRegex(ValueError,'Notification'):
            module.exercise(self.api,self.tmp.name,execute=True)
        self.assertEqual(self.api.puts,[])

    def test_missing_expected_metric_baseline_blocks_before_mutation(self):
        self.api.maximum=0
        with self.assertRaisesRegex(ValueError,'exactly one healthy'):
            module.exercise(self.api,self.tmp.name,execute=True)
        self.assertEqual(self.api.puts,[])


if __name__ == '__main__':
    unittest.main()
