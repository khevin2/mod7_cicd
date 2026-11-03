"""Exercise scanner failure handling and cleanup with local fake tools."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

TRIVY_FAKE = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['FAKE_LOG'], 'a') as f:
    f.write(' '.join(args) + '\n')
out = args[args.index('--output') + 1]
mode = os.environ['FAKE_MODE']
if mode != 'error':
    finding = {'RuleID': 'fake-rule', 'Severity': 'HIGH', 'Match': 'sensitive-fixture-value', 'Code': {'Lines': [{'Content': 'sensitive-fixture-value'}]}}
    report = {'SchemaVersion': 2, 'ArtifactName': 'test-image', 'Results': [{'Secrets': [finding] if mode == 'secret' else [], 'Misconfigurations': [{'ID':'FAKE','Severity':'HIGH'}] if mode == 'misconfig' else []}]}
    with open(out, 'w') as f:
        json.dump(report, f)
sys.exit(1 if mode in ('secret','misconfig') else 2 if mode == 'error' else 0)
'''


class SecurityGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for name in ('scripts', 'bin', 'tmp'):
            (self.root / name).mkdir()
        for name in ('security-scan.sh', 'cleanup-build-image.sh'):
            shutil.copy(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        (self.root / 'bin/trivy').write_text(TRIVY_FAKE)
        (self.root / 'bin/trivy').chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        TMPDIR=str(self.root / 'tmp'), FAKE_LOG=str(self.root / 'tool.log'),
                        IMAGE_REF='mod9-jenkins-webapp:' + 'a' * 40 + '-1')

    def tearDown(self):
        self.tmp.cleanup()

    def run_gate(self, name, mode):
        env = dict(self.env, FAKE_MODE=mode)
        return subprocess.run(['bash', 'scripts/security-scan.sh', name], cwd=self.root,
                              env=env, capture_output=True, text=True)

    def test_image_secret_blocks_and_report_contains_no_raw_matches(self):
        result = self.run_gate('image-secrets', 'secret')
        self.assertNotEqual(result.returncode, 0)
        report = (self.root / 'security-reports/trivy-image-secrets.json').read_text()
        self.assertEqual(json.loads(report)['findingCount'], 1)
        self.assertNotIn('sensitive-fixture-value', report + result.stdout + result.stderr)
        self.assertEqual(list((self.root / 'tmp').iterdir()), [])
        self.assertIn('--scanners secret', (self.root / 'tool.log').read_text())

    def test_clean_image_secret_report_passes(self):
        result = self.run_gate('image-secrets', 'clean')
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads((self.root / 'security-reports/trivy-image-secrets.json').read_text())
        self.assertEqual(report['findingCount'], 0)

    def test_image_secret_scanner_error_fails_closed(self):
        result = self.run_gate('image-secrets', 'error')
        self.assertNotEqual(result.returncode, 0)
        report = json.loads((self.root / 'security-reports/trivy-image-secrets.json').read_text())
        self.assertEqual(report['status'], 'invalid_or_missing_report')
        self.assertEqual(list((self.root / 'tmp').iterdir()), [])

    def test_misconfiguration_blocks_and_preserves_report(self):
        result = self.run_gate('misconfig', 'misconfig')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / 'security-reports/trivy-misconfig.json').exists())
        self.assertIn('--scanners misconfig', (self.root / 'tool.log').read_text())

    def test_sonar_failure_preserves_only_safe_json(self):
        scanner = self.root / 'bin/sonar-scanner'
        scanner.write_text('#!/bin/sh\necho "QUALITY GATE FAILED sensitive-fixture-value" >&2\nexit 1\n')
        scanner.chmod(0o755)
        env = dict(self.env, SONAR_HOST_URL='http://localhost', SONAR_TOKEN='synthetic-token')
        result = subprocess.run(['bash', 'scripts/security-scan.sh', 'sast'], cwd=self.root,
                                env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        report = (self.root / 'security-reports/sonarqube-failure.json').read_text()
        self.assertEqual(json.loads(report)['category'], 'quality_gate_failed')
        self.assertNotIn('sensitive-fixture-value', report + result.stdout + result.stderr)

    def test_cleanup_removes_only_matching_build_tag(self):
        metadata = self.root / 'build-metadata'
        metadata.mkdir()
        expected = 'sha256:' + 'b' * 64
        (metadata / 'scanned-image-id.txt').write_text(expected + '\n')
        docker = self.root / 'bin/docker'
        docker.write_text('#!/bin/sh\nif [ "$2" = inspect ]; then printf "%s\\n" "$FAKE_ID"; else printf "%s\\n" "$*" >> "$FAKE_LOG"; fi\n')
        docker.chmod(0o755)
        env = dict(self.env, FAKE_ID=expected)
        result = subprocess.run(['bash', 'scripts/cleanup-build-image.sh'], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'tool.log').read_text().strip(), 'image rm ' + self.env['IMAGE_REF'])
        (self.root / 'tool.log').unlink()
        env['FAKE_ID'] = 'sha256:' + 'c' * 64
        result = subprocess.run(['bash', 'scripts/cleanup-build-image.sh'], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'tool.log').exists())


if __name__ == '__main__':
    unittest.main()
