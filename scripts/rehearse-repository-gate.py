#!/usr/bin/env python3
"""Compare the repository gate against a historical lockfile in temporary directories."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BASELINE = '9662bf8'


def run_gate(directory):
    env = os.environ.copy()
    env['SECURITY_REPORT_DIR'] = str(directory / 'reports')
    # Use the same pre-populated database for both scans.
    env['TRIVY_SKIP_DB_UPDATE'] = 'true'
    result = subprocess.run(['bash', str(directory / 'scripts/security-scan.sh'), 'repository'],
                            cwd=directory, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    report = directory / 'reports/trivy-repository.json'
    if not report.exists():
        raise ValueError('scanner failed without a report; check Trivy and its vulnerability database')
    data = json.loads(report.read_text())
    if not isinstance(data.get('SchemaVersion'), int) or not isinstance(data.get('ArtifactName'), str):
        raise ValueError('invalid scanner report')
    results = data.get('Results') or []
    if not isinstance(results, list):
        raise ValueError('invalid scanner results')
    findings = sorted({v['VulnerabilityID'] for r in results for v in (r.get('Vulnerabilities') or [])
                       if v.get('Severity') in ('HIGH', 'CRITICAL') and v.get('VulnerabilityID')})
    return result.returncode, findings


def main():
    if not shutil.which('trivy') or not shutil.which('jq'):
        raise ValueError('trivy and jq must be available on PATH')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    with tempfile.TemporaryDirectory(prefix='gate-rehearsal-') as temp:
        outputs = {}
        for name in ('current', 'historical'):
            directory = Path(temp) / name
            (directory / 'scripts').mkdir(parents=True)
            shutil.copy(ROOT / 'scripts/security-scan.sh', directory / 'scripts/security-scan.sh')
            for filename in ('package.json', 'package-lock.json'):
                content = ((ROOT / filename).read_bytes() if name == 'current' else
                           subprocess.check_output(['git', 'show', f'{BASELINE}:{filename}'], cwd=ROOT))
                (directory / filename).write_bytes(content)
            code, findings = run_gate(directory)
            outputs[name] = {'exit_code': code, 'high_critical_ids': findings,
                             'lockfile_sha256': hashlib.sha256((directory / 'package-lock.json').read_bytes()).hexdigest()}
        if outputs['current']['exit_code'] != 0 or outputs['current']['high_critical_ids']:
            raise ValueError('current lockfile did not pass the vulnerability gate')
        if outputs['historical']['exit_code'] != 1 or not outputs['historical']['high_critical_ids']:
            raise ValueError('historical lockfile did not produce a verified gate rejection')
        print(json.dumps({'source_head': source, 'historical_commit': BASELINE,
                          'scope': 'local dependency scan only; no Jenkins or AWS validation',
                          'results': outputs}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(f'Rehearsal failed: {exc}', file=sys.stderr)
        sys.exit(1)
