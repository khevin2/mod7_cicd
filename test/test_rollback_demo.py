"""Test the read-only rollback observer and its fail-closed proof artifact."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
BASELINE='arn:aws:ecs:eu-north-1:447558491229:task-definition/mod9-ecs-app:3'
ATTEMPT='arn:aws:ecs:eu-north-1:447558491229:task-definition/mod9-ecs-app:4'
DIGEST='sha256:'+'a'*64
FAKE=r'''#!/usr/bin/env python3
import json,os,sys
a=sys.argv[1:]
with open('calls.txt','a') as f:f.write(' '.join(a[:2])+'\n')
baseline=os.environ['FAKE_BASELINE'];digest=os.environ['FAKE_DIGEST']
mode=os.environ.get('FAKE_MODE','restored')
if a[:2]==['ecs','describe-services']:
 events=[] if mode=='no-failure-proof' else [{'message':'deployment ecs-svc/demo failed: tasks failed to start'}]
 print(json.dumps({'failures':[],'services':[{'status':'ACTIVE','taskDefinition':baseline,'desiredCount':1,'runningCount':1,'events':events,'deployments':[{'status':'PRIMARY','taskDefinition':baseline,'rolloutState':'COMPLETED'}],'loadBalancers':[{'containerName':'app','containerPort':3000,'targetGroupArn':'group'}]}]}))
elif a[:2]==['ecs','list-tasks']:
 print(json.dumps({'taskArns':['task']}))
elif a[:2]==['ecs','describe-tasks']:
 print(json.dumps({'failures':[],'tasks':[{'taskDefinitionArn':baseline,'lastStatus':'RUNNING','healthStatus':'HEALTHY','containers':[{'name':'app','imageDigest':'sha256:'+'b'*64 if mode=='wrong-digest' else digest}],'attachments':[{'type':'ElasticNetworkInterface','details':[{'name':'privateIPv4Address','value':'10.90.1.2'}]}]}]}))
elif a[:2]==['elbv2','describe-target-health']:
 print(json.dumps({'TargetHealthDescriptions':[{'Target':{'Id':'10.90.1.2','Port':3000},'TargetHealth':{'State':'unhealthy' if mode=='unhealthy-target' else 'healthy'}}]}))
else:sys.exit('Unexpected AWS call '+repr(a))
'''


class RollbackDemoTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        for directory in ['scripts','build-metadata','bin']:(self.root/directory).mkdir()
        shutil.copy(ROOT/'scripts/verify-rollback-demo.sh',self.root/'scripts')
        (self.root/'build-metadata/rollback-baseline.json').write_text(json.dumps({'revision':BASELINE,'imageDigests':[DIGEST]}))
        (self.root/'build-metadata/service-update.json').write_text(json.dumps({'service':{'deployments':[{'id':'ecs-svc/demo','taskDefinition':ATTEMPT}]}}))
        for name,text in [('aws',FAKE),('sleep','#!/bin/sh\nexit 0\n'),('curl','#!/bin/sh\nprintf \'{"service":"jenkins-webapp","status":"ok"}\\n\'\n')]:
            p=self.root/'bin'/name;p.write_text(text);p.chmod(0o755)
        self.env=dict(os.environ,PATH=str(self.root/'bin')+':'+os.environ['PATH'],AWS_REGION='eu-north-1',ECS_CLUSTER='cluster',ECS_SERVICE='service',APP_HEALTH_URL='http://example.invalid/health',FAKE_BASELINE=BASELINE,FAKE_DIGEST=DIGEST,ECS_DEMO_MAX_CHECKS='2')

    def run_observer(self,mode):
        return subprocess.run(['bash','scripts/verify-rollback-demo.sh',ATTEMPT],cwd=self.root,env=dict(self.env,FAKE_MODE=mode),capture_output=True,text=True)

    def test_verified_rollback_still_fails_jenkins_and_writes_proof(self):
        result=self.run_observer('restored')
        self.assertEqual(result.returncode,1,result.stderr)
        proof=json.loads((self.root/'build-metadata/rollback-demo-result.json').read_text())
        self.assertTrue(proof['automaticRollbackVerified'] and proof['imageIdentityVerified'])
        self.assertEqual(proof['restoredRevision'],BASELINE)
        calls=(self.root/'calls.txt').read_text()
        self.assertNotIn('update-service',calls)
        self.assertNotIn('register-task-definition',calls)

    def test_old_healthy_service_without_failure_evidence_is_not_proof(self):
        result=self.run_observer('no-failure-proof')
        self.assertEqual(result.returncode,1)
        self.assertFalse((self.root/'build-metadata/rollback-demo-result.json').exists())

    def test_wrong_restored_digest_blocks_proof(self):
        result=self.run_observer('wrong-digest')
        self.assertEqual(result.returncode,1)
        self.assertFalse((self.root/'build-metadata/rollback-demo-result.json').exists())

    def test_unhealthy_restored_target_blocks_proof(self):
        result=self.run_observer('unhealthy-target')
        self.assertEqual(result.returncode,1)
        self.assertFalse((self.root/'build-metadata/rollback-demo-result.json').exists())


if __name__=='__main__':unittest.main()
