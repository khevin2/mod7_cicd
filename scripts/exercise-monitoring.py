#!/usr/bin/env python3
"""Operator-run, reversible real-metric alarm test. Default: prepare only."""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import subprocess
import time

ALARM = 'mod9-ecs-no-healthy-targets'
ACCOUNT = '447558491229'
REGION = 'eu-north-1'
INPUT_FIELDS = {
    'AlarmName', 'AlarmDescription', 'ActionsEnabled', 'OKActions', 'AlarmActions',
    'InsufficientDataActions', 'MetricName', 'Namespace', 'Statistic',
    'ExtendedStatistic', 'Dimensions', 'Period', 'Unit', 'EvaluationPeriods',
    'DatapointsToAlarm', 'Threshold', 'ComparisonOperator', 'TreatMissingData',
    'EvaluateLowSampleCountPercentile', 'Metrics', 'ThresholdMetricId',
}


class Aws:
    def __init__(self, profile):
        self.profile = profile

    def __call__(self, service, operation, **payload):
        command = ['aws', '--profile', self.profile, '--region', REGION, service, operation,
                   '--output', 'json']
        if payload:
            command += ['--cli-input-json', json.dumps(payload)]
        result = subprocess.check_output(command, text=True)
        return json.loads(result) if result.strip() else {}


def read_alarm(api):
    response = api('cloudwatch', 'describe-alarms', AlarmNames=[ALARM])
    if len(response.get('MetricAlarms', [])) != 1:
        raise ValueError('Expected the existing demo availability alarm')
    return response['MetricAlarms'][0]


def configuration(alarm):
    return {key: value for key, value in alarm.items() if key in INPUT_FIELDS}


def prepare(alarm):
    original = configuration(alarm)
    if (original.get('AlarmName') != ALARM or original.get('Namespace') != 'AWS/ApplicationELB'
            or original.get('MetricName') != 'HealthyHostCount'
            or original.get('Statistic') != 'Maximum' or original.get('Period') != 60
            or original.get('EvaluationPeriods') != 3
            or original.get('ComparisonOperator') != 'LessThanThreshold'
            or original.get('Threshold') != 1 or alarm.get('StateValue') != 'OK'):
        raise ValueError('Expected the healthy baseline availability alarm; refusing to alter another configuration')
    if any(original.get(key) for key in ['AlarmActions', 'OKActions', 'InsufficientDataActions']):
        raise ValueError('Notification actions are configured; this no-notification test will not run')
    if {x['Name'] for x in original.get('Dimensions', [])} != {'LoadBalancer', 'TargetGroup'}:
        raise ValueError('Expected the ALB and target-group metric dimensions')
    trial = dict(original, Threshold=2)
    return original, trial


def wait_for_state(api, expected, config, timeout, interval):
    deadline = time.monotonic() + timeout
    while True:
        alarm = read_alarm(api)
        if configuration(alarm) != config:
            raise RuntimeError('Alarm configuration changed during the test; inspect saved configuration')
        print(f'Waiting for {expected}: current state {alarm["StateValue"]}', flush=True)
        if alarm['StateValue'] == expected:
            return alarm
        if time.monotonic() >= deadline:
            raise TimeoutError('Alarm did not reach ' + expected)
        time.sleep(interval)


def exercise(api, directory, execute=False, timeout=480, interval=15):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    original, trial = prepare(read_alarm(api))
    now = datetime.now(timezone.utc)
    data = api('cloudwatch', 'get-metric-statistics', Namespace=original['Namespace'],
               MetricName=original['MetricName'], Dimensions=original['Dimensions'],
               StartTime=(now - timedelta(minutes=10)).isoformat(), EndTime=now.isoformat(),
               Period=60, Statistics=['Maximum'])
    points = sorted(data.get('Datapoints', []), key=lambda item: item['Timestamp'])
    if not points:
        raise ValueError('No real ALB metric datapoints are available')
    latest = points[-1]
    age = (now - datetime.fromisoformat(latest['Timestamp'].replace('Z', '+00:00'))).total_seconds()
    if latest.get('Maximum') != 1 or not 0 <= age <= 240:
        raise ValueError('Wait for a fresh datapoint with exactly one healthy target before testing')
    for name, payload in [('alarm-original.json', original), ('alarm-demo.json', trial),
                          ('metric-before.json', data)]:
        (directory / name).write_text(json.dumps(payload, indent=2) + '\n')
    result = dict(status='PREPARED', alarm=ALARM, originalThreshold=1, demoThreshold=2,
                  realMetricVerified=True, notificationActionsConfigured=False)
    report = directory / 'monitoring-demo-result.json'
    report.write_text(json.dumps(result, indent=2) + '\n')
    if not execute:
        print('Prepared local alarm configurations only; use --execute to run the test.', flush=True)
        return result
    print('Testing real metric evaluation: temporary threshold 2 with one healthy target.', flush=True)
    print('Original configuration saved at ' + str(directory / 'alarm-original.json'), flush=True)
    failure = None
    try:
        api('cloudwatch', 'put-metric-alarm', **trial)
        result['alarmObserved'] = wait_for_state(api, 'ALARM', trial, timeout, interval)['StateValue'] == 'ALARM'
    except BaseException as error:
        failure = error
        result['status'] = 'FAILED'
    finally:
        # Restore even after timeout, CLI errors, or an operator interrupt. Never
        # overwrite an unrelated concurrent configuration change.
        current = configuration(read_alarm(api))
        if current == trial:
            api('cloudwatch', 'put-metric-alarm', **original)
        elif current != original:
            raise RuntimeError('Unexpected concurrent alarm change; use the saved original only after reviewing it')
        result['originalConfigurationRestored'] = configuration(read_alarm(api)) == original
        result['recoveryObserved'] = wait_for_state(api, 'OK', original, timeout, interval)['StateValue'] == 'OK'
        result['status'] = 'FAILED' if failure else 'PASS'
        history = api('cloudwatch', 'describe-alarm-history', AlarmName=ALARM,
                      HistoryItemType='StateUpdate', StartDate=now.isoformat())
        (directory / 'alarm-history.json').write_text(json.dumps(history, indent=2) + '\n')
        report.write_text(json.dumps(result, indent=2) + '\n')
    if failure:
        raise failure
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', default='training')
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    api = Aws(args.profile)
    if api('sts', 'get-caller-identity')['Account'] != ACCOUNT:
        raise ValueError('Unexpected AWS account')
    directory = args.output_dir or Path('build-metadata') / ('monitoring-demo-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    result = exercise(api, directory, args.execute)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
