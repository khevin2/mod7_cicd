"""Exercise bootstrap convergence/failure behavior without a live service."""
import copy
import io
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

MODULE = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'ansible/files/configure-sonarqube.py'))
configure = MODULE['configure']
ApiError = MODULE['ApiError']


class FakeServer:
    def __init__(self, mqr=True):
        self.admin_password = 'admin'
        self.analysis_password = None
        self.project = False
        self.permissions = set()
        self.gate = False
        self.conditions = []
        self.selected = False
        self.token = None
        self.token_name = False
        self.generations = 0
        self.posts = []
        self.fail = None
        self.mqr = mqr
        self.analysis_is_admin = False

    def client(self, base, login, password):
        server = self

        class Client:
            def valid(self):
                return ((login == 'admin' and password == server.admin_password) or
                        (login == MODULE['LOGIN'] and password == server.analysis_password) or
                        (server.token is not None and login == server.token and password == ''))

            def request(self, path, params=None, post=False, text=False):
                params = params or {}
                if path == server.fail:
                    raise ApiError(path, 503)
                if post:
                    server.posts.append(path)
                if path == '/api/server/version':
                    return 'test-server'
                if path == '/api/settings/values':
                    return {'settings': [
                        {'key': 'sonar.forceAuthentication', 'value': 'true'},
                        {'key': 'sonar.multi-quality-mode.enabled', 'value': str(server.mqr).lower()},
                    ]}
                if path == '/api/users/change_password':
                    if params['login'] == 'admin':
                        server.admin_password = params['password']
                    else:
                        server.analysis_password = params['password']
                    return {}
                if path == '/api/projects/search':
                    return {'components': [{'key': MODULE['PROJECT']}] if server.project else []}
                if path == '/api/projects/create':
                    server.project = True
                    return {}
                if path == '/api/users/search':
                    return {'users': [{'login': MODULE['LOGIN'], 'local': True}] if server.analysis_password else []}
                if path == '/api/users/create':
                    server.analysis_password = params['password']
                    return {}
                if path == '/api/permissions/users':
                    return {'users': [{'login': MODULE['LOGIN'], 'permissions': list(server.permissions)}]}
                if path == '/api/permissions/add_user':
                    server.permissions.add(params['permission'])
                    return {}
                if path == '/api/qualitygates/list':
                    return {'qualitygates': [{'name': MODULE['GATE']}] if server.gate else []}
                if path == '/api/qualitygates/create':
                    server.gate = True
                    # Current SonarQube creates factory conditions automatically.
                    server.conditions = [{'id': 'factory', 'metric': 'new_coverage', 'op': 'LT', 'error': '80'}]
                    return {'name': MODULE['GATE']}
                if path == '/api/qualitygates/show':
                    return {'conditions': copy.deepcopy(server.conditions)}
                if path == '/api/qualitygates/delete_condition':
                    server.conditions = [c for c in server.conditions if c['id'] != params['id']]
                    return {}
                if path == '/api/qualitygates/create_condition':
                    assert params['gateName'] == MODULE['GATE']
                    server.conditions.append({'id': 'managed', **{k: params[k] for k in ['metric', 'op', 'error']}})
                    return {}
                if path == '/api/qualitygates/update_condition':
                    server.conditions = [{k: params[k] for k in ['id', 'metric', 'op', 'error']}]
                    return {}
                if path == '/api/qualitygates/get_by_project':
                    return {'qualityGate': {'name': MODULE['GATE'] if server.selected else 'Sonar way'}}
                if path == '/api/qualitygates/select':
                    assert params['gateName'] == MODULE['GATE']
                    server.selected = True
                    return {}
                if path == '/api/users/current':
                    return {'login': MODULE['LOGIN'], 'permissions': {'global': ['admin'] if server.analysis_is_admin else []}}
                if path == '/api/user_tokens/search':
                    return {'userTokens': [{'name': MODULE['TOKEN_NAME']}] if server.token_name else []}
                if path == '/api/user_tokens/revoke':
                    server.token_name = False
                    server.token = None
                    return {}
                if path == '/api/user_tokens/generate':
                    server.generations += 1
                    server.token_name = True
                    server.token = 'test-token-' + str(server.generations).zfill(20)
                    return {'token': server.token}
                raise AssertionError('Unhandled mock route: ' + path)

        return Client()


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'token'
        self.config = {'admin_password': 'test-admin-password', 'analysis_password': 'test-analysis-password',
                       'token_file': str(self.path)}
        self.server = FakeServer()

    def run_bootstrap(self):
        return configure(self.config, factory=self.server.client)

    def test_initial_configuration_and_no_mutations_on_second_run(self):
        result = self.run_bootstrap()
        self.assertTrue(result['changed'])
        self.assertEqual(result['metric'], 'software_quality_security_rating')
        self.assertEqual(self.server.permissions, {'user', 'scan'})
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        before = self.path.read_bytes()
        self.server.posts.clear()
        self.assertFalse(self.run_bootstrap()['changed'])
        self.assertEqual(self.server.posts, [])
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(self.server.generations, 1)

    def test_standard_mode_uses_standard_security_metric(self):
        self.server.mqr = False
        self.assertEqual(self.run_bootstrap()['metric'], 'security_rating')

    def test_unknown_admin_password_fails_before_mutation(self):
        self.server.admin_password = 'different-existing-password'
        with self.assertRaises(RuntimeError):
            self.run_bootstrap()
        self.assertEqual(self.server.posts, [])
        self.assertFalse(self.path.exists())

    def test_unexpected_gate_drift_is_not_deleted(self):
        self.run_bootstrap()
        self.server.conditions.append({'id': 'unmanaged', 'metric': 'new_coverage', 'op': 'LT', 'error': '90'})
        self.server.posts.clear()
        with self.assertRaises(RuntimeError):
            self.run_bootstrap()
        self.assertNotIn('/api/qualitygates/delete_condition', self.server.posts)

    def test_invalid_token_is_replaced_and_not_printed(self):
        self.run_bootstrap()
        old = self.path.read_text()
        self.server.token = None
        result = self.run_bootstrap()
        self.assertEqual(result['changes'], ['analysis_token'])
        self.assertNotEqual(old, self.path.read_text())
        self.assertNotIn(self.path.read_text(), str(result))

    def test_interrupted_factory_condition_cleanup_resumes(self):
        self.server.fail = '/api/qualitygates/delete_condition'
        with self.assertRaises(ApiError):
            self.run_bootstrap()
        self.assertFalse(self.path.exists())
        self.server.fail = None
        self.assertTrue(self.run_bootstrap()['changed'])
        self.assertEqual(len(self.server.conditions), 1)
        self.assertEqual(self.server.conditions[0]['metric'], 'software_quality_security_rating')

    def test_failed_condition_creation_does_not_create_a_token(self):
        self.server.fail = '/api/qualitygates/create_condition'
        with self.assertRaises(ApiError):
            self.run_bootstrap()
        self.assertFalse(self.path.exists())

    def test_weaker_threshold_is_corrected(self):
        self.run_bootstrap()
        self.server.conditions[0]['error'] = '2'
        self.assertIn('quality_gate_threshold', self.run_bootstrap()['changes'])
        self.assertEqual(self.server.conditions[0]['error'], '1')

    def test_privileged_analysis_account_is_rejected(self):
        self.server.analysis_is_admin = True
        with self.assertRaises(RuntimeError):
            self.run_bootstrap()
        self.assertFalse(self.path.exists())

    def test_http_error_does_not_expose_response_body_or_password(self):
        client = MODULE['Client']('http://127.0.0.1:9000', 'admin', 'private-test-input')
        error = urllib.error.HTTPError('http://127.0.0.1:9000/api/example', 400, 'bad request', {}, io.BytesIO(b'private-test-input'))
        with patch('urllib.request.urlopen', side_effect=error):
            with self.assertRaises(ApiError) as context:
                client.request('/api/example', {'password': 'private-test-input'}, post=True)
        self.assertNotIn('private-test-input', str(context.exception))


if __name__ == '__main__':
    unittest.main()
