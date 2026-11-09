#!/usr/bin/env python3
"""Read plugin archives and report differences from the complete checksum lock."""
import hashlib
import json
from pathlib import Path
import sys


def audit(directory, plugins):
    expected = {p['name']: p for p in plugins}
    unexpected = []
    disabled = []
    mismatched = []
    directory = Path(directory)
    for path in directory.iterdir():
        if path.suffix in ('.jpi', '.hpi'):
            if path.stem not in expected or path.suffix != '.jpi':
                unexpected.append(path.name)
        if path.name.endswith(('.jpi.disabled', '.hpi.disabled')):
            disabled.append(path.name)
    for name, plugin in expected.items():
        path = directory / (name + '.jpi')
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != plugin['sha256']:
            mismatched.append(name)
    return {'unexpected': sorted(unexpected), 'disabled': sorted(disabled),
            'mismatched': sorted(mismatched)}


if __name__ == '__main__':
    lock = json.loads(Path(sys.argv[1]).read_text())
    print(json.dumps(audit(sys.argv[2], lock['ci_jenkins_plugins'])))
