"""Run the actual Jenkins Ansible tasks against a local HTTP fixture."""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

try:
    import yaml
except ImportError:
    yaml = None

ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'b' * 40
IMAGE = '447558491229.dkr.ecr.eu-north-1.amazonaws.com/mod9-ecs@sha256:' + 'a' * 64
REVISION = 'arn:aws:ecs:eu-north-1:447558491229:task-definition/mod9-ecs-app:2'


@unittest.skipUnless(yaml is not None and shutil.which('ansible-playbook'), 'Ansible controller/PyYAML required')
class JenkinsAnsibleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.posts = 0
        self.commit = COMMIT
        self.release = False
        fixture = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                self.rfile.read(int(self.headers.get('Content-Length', '0')))
                fixture.posts += 1
                self.send_response(201)
                self.send_header('Location', f'http://127.0.0.1:{self.server.server_port}/queue/item/42/')
                self.end_headers()

            def do_GET(self):
                path = self.path
                if path.startswith('/crumbIssuer/'):
                    data = {'crumbRequestField':'Jenkins-Crumb','crumb':'fixture'}
                elif path.startswith('/queue/item/42/'):
                    data = {'executable':{'number':7}}
                elif path.endswith('/artifact/build-metadata/git-commit.txt'):
                    data = fixture.commit + '\n'
                elif path.endswith('/artifact/build-metadata/image-digest.txt'):
                    data = IMAGE + '\n'
                elif path.endswith('/artifact/build-metadata/task-definition-arn.txt'):
                    data = REVISION + '\n'
                elif path.startswith('/job/mod9-secure-ecs/7/api/json'):
                    data = {'number':7,'building':False,'result':'SUCCESS',
                            'actions':[{'parameters':[{'name':'RELEASE_APPROVED','value':fixture.release},
                                                      {'name':'PUBLISH_APPROVED','value':True}]}]}
                else:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain' if isinstance(data,str) else 'application/json')
                self.end_headers()
                self.wfile.write((data if isinstance(data,str) else json.dumps(data)).encode())

        try:
            self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        except PermissionError:
            self.skipTest('Sandbox disallows the local HTTP test socket')
        self.addCleanup(self.server.server_close)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.shutdown)
        # Execute the real modified play, with only transport/platform changed.
        source = (ROOT/'ansible/playbooks/run_ci_validation.yml').read_text()
        source = source.replace('http://127.0.0.1:8080', f'http://127.0.0.1:{self.server.server_port}')
        play = yaml.safe_load(source)[2]
        play.update(hosts='localhost', connection='local', become=False)
        play['vars_files'] = [str(ROOT/'ansible/vars/ci-versions.yml')]
        bootstrap = dict(name='Fixture source identity', hosts='localhost', connection='local', gather_facts=False,
                         tasks=[{'ansible.builtin.set_fact':{'ci_local_commit':{'stdout':COMMIT}}}])
        self.playbook = self.root/'test.yml'
        self.playbook.write_text(yaml.safe_dump([bootstrap,play],sort_keys=False))
        self.record = self.root/'build.json'

    def run_play(self, **overrides):
        extra = dict(ci_jenkins_admin_password='fixture-only', ci_publish_approved=True,
                     ci_release_approved=self.release, ci_run_record_path=str(self.record))
        extra.update(overrides)
        return subprocess.run(['ansible-playbook','-i','localhost,',str(self.playbook),'-e',json.dumps(extra)],
                              env=dict(os.environ,ANSIBLE_LOCAL_TEMP=str(self.root/'ansible-tmp'),ANSIBLE_NOCOLOR='1'),
                              capture_output=True,text=True,timeout=120)

    def test_publish_and_resume_exact_build_export_identity_without_duplicate_post(self):
        first = self.run_play()
        self.assertEqual(first.returncode,0,first.stdout+first.stderr)
        record = json.loads(self.record.read_text())
        self.assertEqual(record['result'],'SUCCESS')
        self.assertEqual(record['image_digest'],IMAGE)
        self.assertEqual(record['source_commit'],COMMIT)
        self.assertEqual(record['task_definition_arn'],'')
        second = self.run_play(ci_resume_validation=True,ci_resume_build_number=7)
        self.assertEqual(second.returncode,0,second.stdout+second.stderr)
        self.assertEqual(self.posts,1)

    def test_resumed_queue_exports_exact_release_revision(self):
        self.release = True
        result = self.run_play(ci_resume_queue_id=42)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(self.posts,0)
        self.assertEqual(json.loads(self.record.read_text())['task_definition_arn'],REVISION)

    def test_wrong_source_cannot_produce_successful_record(self):
        self.commit = 'c' * 40
        result = self.run_play(ci_resume_queue_id=42)
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('result',json.loads(self.record.read_text()))

    def test_recovered_build_with_wrong_approval_is_rejected(self):
        self.release = True
        result = self.run_play(ci_resume_validation=True,ci_resume_build_number=7,ci_release_approved=False)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.posts,0)
        self.assertFalse(self.record.exists())


if __name__ == '__main__':
    unittest.main()
