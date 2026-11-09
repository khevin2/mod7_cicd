#!/usr/bin/env python3
"""Cold-start the managed Jenkins configuration locally, never on EC2.

Requires Java 21 and a local --artifacts directory containing jenkins.war and
checksum-locked plugins/*.jpi. Uses disposable credentials and a loopback port.
The test does not run builds, clone SCM, or deploy anything.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

from jinja2 import Environment, StrictUndefined
import yaml


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--war', type=Path, help='Optional alternative path to the identical pinned core WAR')
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    lock = json.loads((repo / 'ansible/vars/ci-jenkins-plugins.json').read_text())
    variables = yaml.safe_load((repo / 'ansible/vars/ci-versions.yml').read_text())
    variables.update(yaml.safe_load((repo / 'ansible/vars/ci-security-tools.yml').read_text()))
    variables['ci_casc_credentials_ready'] = True
    work = Path(tempfile.mkdtemp(prefix='mod9-jenkins-bootstrap-', dir='/tmp'))
    home = work / 'home'
    (home / 'plugins').mkdir(parents=True)
    secret_dir = work / 'secrets'
    secret_dir.mkdir(mode=0o700)
    password = secrets.token_urlsafe(32)
    password_file = secret_dir / 'CI_JENKINS_ADMIN_PASSWORD'
    password_file.write_text(password)
    password_file.chmod(0o600)
    for name in ['CI_SONAR_TOKEN', 'CI_SNYK_TOKEN']:
        secret = secret_dir / name
        secret.write_text(secrets.token_urlsafe(32))
        secret.chmod(0o600)
    for plugin in lock['ci_jenkins_plugins']:
        source = args.artifacts / 'plugins' / (plugin['name'] + '.jpi')
        if hashlib.sha256(source.read_bytes()).hexdigest() != plugin['sha256']:
            raise ValueError('Plugin checksum mismatch: ' + plugin['name'])
        shutil.copy2(source, home / 'plugins' / source.name)
    env = Environment(undefined=StrictUndefined)
    env.filters['to_json'] = json.dumps
    templates = repo / 'ansible/templates'
    job = work / 'pipeline.groovy'
    job.write_text(env.from_string((templates / 'ci-jenkins-job.groovy.j2').read_text()).render(**variables))
    casc = work / 'casc.yml'
    casc.write_text(env.from_string((templates / 'ci-jenkins-casc.yml.j2').read_text()).render(**variables)
                    .replace('/etc/jenkins/mod9-pipeline.groovy', str(job)))
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    base = f'http://127.0.0.1:{port}'
    auth = base64.b64encode(f"{variables['ci_jenkins_admin_id']}:{password}".encode()).decode()

    def read(path, authenticated=True):
        request = urllib.request.Request(base + path)
        if authenticated:
            request.add_header('Authorization', 'Basic ' + auth)
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.load(response)

    process_env = dict(os.environ, JENKINS_HOME=str(home), CASC_JENKINS_CONFIG=str(casc), SECRETS=str(secret_dir))
    process = None
    success = False
    try:
        with (work / 'jenkins.log').open('w') as log:
            process = subprocess.Popen([
                'java', '-Xms128m', '-Xmx384m', '-Djava.awt.headless=true',
                '-Djenkins.install.runSetupWizard=false', '-jar', str(args.war or args.artifacts / 'jenkins.war'),
                '--httpListenAddress=127.0.0.1', f'--httpPort={port}',
                '--webroot=' + str(work / 'webroot'),
            ], env=process_env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + args.timeout
            while True:
                if process.poll() is not None:
                    raise RuntimeError('Jenkins exited before becoming ready')
                try:
                    actual = read('/pluginManager/api/json?tree=plugins[shortName,version,active,enabled]')
                    break
                except (OSError, urllib.error.HTTPError):
                    if time.monotonic() > deadline:
                        raise RuntimeError('Jenkins readiness timed out')
                    time.sleep(2)
            actual = {p['shortName']: p for p in actual['plugins']}
            assert set(actual) == {p['name'] for p in lock['ci_jenkins_plugins']}, 'Plugin set differs'
            for plugin in lock['ci_jenkins_plugins']:
                observed = actual[plugin['name']]
                assert observed['version'] == plugin['version'], plugin['name']
                assert observed['active'] and observed['enabled'], plugin['name']
            config = read('/api/json?tree=numExecutors,useSecurity')
            assert config['numExecutors'] == 1 and config['useSecurity'], 'Executor/security configuration differs'
            assert read('/job/mod9-secure-ecs/api/json?tree=disabled')['disabled'], 'Seeded job must remain disabled'
            try:
                read('/api/json', authenticated=False)
            except urllib.error.HTTPError as error:
                assert error.code in [401, 403], 'Unexpected anonymous status'
            else:
                raise AssertionError('Anonymous API access was allowed')
            print(f"PASS: {len(actual)} exact plugins loaded; Vault-style file secret login, one executor, anonymous denial and disabled SCM job verified.")
            success = True
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        if success:
            shutil.rmtree(work)
        else:
            print(f'Local test failed. Inspect {work}/jenkins.log privately; temporary credentials are stored in this restricted directory.')


if __name__ == '__main__':
    main()
