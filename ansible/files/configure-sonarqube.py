#!/usr/bin/env python3
"""Operator-run SonarQube bootstrap. Secrets arrive on stdin, never argv.

Only the Ansible playbook executes this on EC2. API failures stop provisioning;
stdout contains non-secret change metadata, not tokens or HTTP response bodies.
"""
import base64
from datetime import date, timedelta
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

PROJECT = 'mod9-jenkins-webapp'
GATE = 'mod9-strict-security'
LOGIN = 'jenkins-analysis'
TOKEN_NAME = 'mod9-jenkins-analysis'


class ApiError(Exception):
    def __init__(self, path, status):
        self.path, self.status = path, status
        super().__init__(f'{path}: HTTP {status}')


class Client:
    def __init__(self, base, login, password):
        self.base = base
        self.authorization = 'Basic ' + base64.b64encode(f'{login}:{password}'.encode()).decode()

    def request(self, path, params=None, post=False, text=False):
        encoded = urllib.parse.urlencode(params or {}).encode()
        url = self.base + path
        if not post and encoded:
            url += '?' + encoded.decode()
        request = urllib.request.Request(url, data=encoded if post else None,
                                         headers={'Authorization': self.authorization})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read()
        except urllib.error.HTTPError as error:
            # Never print the server body: it may echo a sensitive input.
            raise ApiError(path, error.code) from None
        if text:
            return data.decode().strip()
        return json.loads(data) if data.strip() else {}

    def valid(self):
        try:
            return self.request('/api/authentication/validate').get('valid') is True
        except ApiError as error:
            if error.status in (401, 403):
                return False
            raise


def atomic_secret(path, value):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.sonar-token-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(value)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def configure(config, factory=Client):
    base = 'http://127.0.0.1:9000'
    changes = []
    admin = factory(base, 'admin', config['admin_password'])
    if not admin.valid():
        initial = factory(base, 'admin', 'admin')
        if not initial.valid():
            raise RuntimeError('Administrator authentication failed; check the Vault input privately.')
        initial.request('/api/users/change_password', {
            'login': 'admin', 'previousPassword': 'admin', 'password': config['admin_password'],
        }, post=True)
        if not admin.valid():
            raise RuntimeError('Administrator password change could not be verified.')
        changes.append('administrator_password')

    version = admin.request('/api/server/version', text=True)
    settings = admin.request('/api/settings/values', {
        'keys': 'sonar.forceAuthentication,sonar.multi-quality-mode.enabled',
    }).get('settings', [])
    values = {s['key']: s.get('value') for s in settings}
    if values.get('sonar.forceAuthentication') != 'true':
        admin.request('/api/settings/set', {'key': 'sonar.forceAuthentication', 'value': 'true'}, post=True)
        changes.append('force_authentication')

    projects = admin.request('/api/projects/search', {'projects': PROJECT}).get('components', [])
    existing_project = next((p for p in projects if p['key'] == PROJECT), None)
    if existing_project and existing_project.get('visibility', 'private') != 'private':
        raise RuntimeError('Existing project visibility differs from the private lab policy; review drift.')
    if not any(p['key'] == PROJECT for p in projects):
        admin.request('/api/projects/create', {
            'project': PROJECT, 'name': PROJECT, 'visibility': 'private',
        }, post=True)
        changes.append('project')

    users = admin.request('/api/users/search', {'q': LOGIN, 'ps': 100}).get('users', [])
    user = next((u for u in users if u['login'] == LOGIN), None)
    analysis = factory(base, LOGIN, config['analysis_password'])
    if user is None:
        admin.request('/api/users/create', {
            'login': LOGIN, 'name': 'Jenkins analysis', 'local': 'true', 'password': config['analysis_password'],
        }, post=True)
        changes.append('analysis_user')
    elif user.get('local') is False or user.get('externalProvider') not in (None, 'sonarqube'):
        raise RuntimeError('The analysis login exists with an external identity; review instead of replacing it.')
    elif not analysis.valid():
        admin.request('/api/users/change_password', {'login': LOGIN, 'password': config['analysis_password']}, post=True)
        changes.append('analysis_password')
    if not analysis.valid():
        raise RuntimeError('Analysis account authentication could not be verified.')
    identity = analysis.request('/api/users/current')
    if identity.get('login') != LOGIN or 'admin' in identity.get('permissions', {}).get('global', []):
        raise RuntimeError('The dedicated analysis account must not have system administrator privileges.')

    permission_users = admin.request('/api/permissions/users', {'projectKey': PROJECT, 'q': LOGIN, 'ps': 100}).get('users', [])
    permissions = next((u.get('permissions', []) for u in permission_users if u['login'] == LOGIN), [])
    for permission in ('user', 'scan'):
        if permission not in permissions:
            admin.request('/api/permissions/add_user', {
                'projectKey': PROJECT, 'login': LOGIN, 'permission': permission,
            }, post=True)
            changes.append('project_permission_' + permission)

    # Require overall security rating A: stricter than just blocking High/Critical.
    # Match the server's configured Standard/MQR mode rather than disabling it.
    metric = ('security_rating' if values.get('sonar.multi-quality-mode.enabled') == 'false'
              else 'software_quality_security_rating')
    gates = admin.request('/api/qualitygates/list').get('qualitygates', [])
    state_path = Path(config['token_file'] + '.bootstrap-state.json')
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    if not any(g['name'] == GATE for g in gates):
        # SonarQube creates gates with factory CAYC conditions. Record intent
        # before creation so an interrupted first run can resume safely.
        state = {'gate': GATE, 'defaults_pending': True}
        atomic_secret(state_path, json.dumps(state))
        admin.request('/api/qualitygates/create', {'name': GATE}, post=True)
        changes.append('quality_gate')
    shown = admin.request('/api/qualitygates/show', {'name': GATE})
    conditions = shown.get('conditions', [])
    if state.get('gate') == GATE and state.get('defaults_pending'):
        if any(not c['metric'].startswith('new_') for c in conditions):
            raise RuntimeError('Unexpected conditions during initial managed gate creation; review drift.')
        for condition in conditions:
            admin.request('/api/qualitygates/delete_condition', {'id': condition['id']}, post=True)
        atomic_secret(state_path, json.dumps({'gate': GATE, 'defaults_pending': False}))
        if conditions:
            changes.append('replace_factory_conditions_with_overall_security_policy')
        conditions = admin.request('/api/qualitygates/show', {'name': GATE}).get('conditions', [])
    if len(conditions) > 1 or (conditions and conditions[0]['metric'] != metric):
        raise RuntimeError('Managed quality gate has unexpected conditions; review drift instead of deleting conditions.')
    if not conditions:
        admin.request('/api/qualitygates/create_condition', {
            'gateName': GATE, 'metric': metric, 'op': 'GT', 'error': '1',
        }, post=True)
        changes.append('quality_gate_condition')
    elif conditions[0].get('op') != 'GT' or str(conditions[0].get('error')) != '1':
        admin.request('/api/qualitygates/update_condition', {
            'id': conditions[0]['id'], 'metric': metric, 'op': 'GT', 'error': '1',
        }, post=True)
        changes.append('quality_gate_threshold')
    selected = admin.request('/api/qualitygates/get_by_project', {'project': PROJECT}).get('qualityGate', {})
    if selected.get('name') != GATE:
        admin.request('/api/qualitygates/select', {'projectKey': PROJECT, 'gateName': GATE}, post=True)
        changes.append('project_quality_gate')

    path = Path(config['token_file'])
    valid_token = False
    if path.exists():
        token_client = factory(base, path.read_text().strip(), '')
        if token_client.valid():
            current = token_client.request('/api/users/current')
            valid_token = current.get('login') == LOGIN
    if not valid_token:
        existing = analysis.request('/api/user_tokens/search').get('userTokens', [])
        if any(t['name'] == TOKEN_NAME for t in existing):
            analysis.request('/api/user_tokens/revoke', {'name': TOKEN_NAME}, post=True)
        generated = analysis.request('/api/user_tokens/generate', {
            'name': TOKEN_NAME, 'type': 'USER_TOKEN',
            'expirationDate': (date.today() + timedelta(days=30)).isoformat(),
        }, post=True)
        token = generated.get('token')
        if not isinstance(token, str) or not token or not factory(base, token, '').valid():
            raise RuntimeError('Generated analysis token failed validation.')
        atomic_secret(path, token)
        changes.append('analysis_token')

    # Confirm the final gate using the exact server response, not POST success alone.
    final = admin.request('/api/qualitygates/show', {'name': GATE}).get('conditions', [])
    if len(final) != 1 or final[0]['metric'] != metric or final[0]['op'] != 'GT' or str(final[0]['error']) != '1':
        raise RuntimeError('Final quality gate verification failed.')
    return {'changed': bool(changes), 'changes': changes, 'project': PROJECT,
            'gate': GATE, 'metric': metric, 'server_version': version}


if __name__ == '__main__':
    try:
        result = configure(json.load(sys.stdin))
        print(json.dumps(result))
    except ApiError as error:
        print(json.dumps({'failed': True, 'endpoint': error.path, 'http_status': error.status}), file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        # Exception text from third-party parsers/network stacks is not safe to archive.
        print(json.dumps({'failed': True, 'category': type(error).__name__,
                          'diagnostic': 'Bootstrap failed; check API compatibility, Vault inputs and managed-state drift privately.'}), file=sys.stderr)
        sys.exit(1)
