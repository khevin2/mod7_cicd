#!/usr/bin/env python3
"""Resolve Jenkins plugin roots + mandatory dependencies into a checksum lock.

Reads public update metadata only. Writes JSON (valid Ansible YAML) to stdout;
redirect deliberately to refresh the checked-in lock. Provisioning never runs
this resolver and never selects 'latest'.
"""
import argparse
import base64
from datetime import datetime
import json
import re
import urllib.request

UPDATE_CENTER = "https://updates.jenkins.io/current/plugin-versions.json"
ROOTS = ["configuration-as-code", "job-dsl", "workflow-aggregator", "git",
         "github", "credentials-binding", "nodejs", "timestamper", "junit"]


def core_version(value):
    if not re.fullmatch(r"\d+(?:\.\d+)+", value):
        raise ValueError(f"Unsupported Jenkins core version: {value}")
    parts = tuple(int(x) for x in value.split('.'))
    return parts + (0,) * (4 - len(parts))


def resolve(metadata, version, roots):
    catalog = metadata["plugins"]
    selected = {}
    pending = list(roots)
    while pending:
        name = pending.pop()
        if name in selected:
            continue
        compatible = [p for p in catalog[name].values()
                      if core_version(p['requiredCore']) <= core_version(version)]
        if not compatible:
            raise ValueError(f"No {name} release supports core {version}")
        plugin = max(compatible, key=lambda p: datetime.fromisoformat(p['releaseTimestamp'].replace('Z', '+00:00')))
        digest = base64.b64decode(plugin["sha256"], validate=True).hex()
        if len(digest) != 64:
            raise ValueError(f"Missing SHA256 for {name}")
        url = plugin["url"]
        if not url.startswith("https://updates.jenkins.io/download/plugins/"):
            raise ValueError(f"Unexpected plugin URL: {url}")
        # The official archive avoids country-specific update mirror redirects.
        url = url.replace("https://updates.jenkins.io/download/plugins/", "https://archives.jenkins.io/plugins/")
        required = [d for d in plugin.get("dependencies", []) if not d.get("optional", False)]
        # Reject dependency baselines whose core is newer than our fixed core.
        for dependency in required:
            minimum = catalog[dependency['name']][dependency['version']]
            if core_version(minimum['requiredCore']) > core_version(version):
                raise ValueError(f"{name} requires incompatible dependency {dependency['name']}")
        mandatory = [d["name"] for d in required]
        pending.extend(mandatory)
        selected[name] = {
            "name": name, "version": plugin["version"], "url": url,
            "sha256": digest, "required_core": plugin["requiredCore"],
            "dependencies": mandatory,
            "minimum_dependencies": [{'name': d['name'], 'version': d['version']} for d in required],
        }
    return {
        "ci_jenkins_version": version,
        "ci_jenkins_plugin_metadata": UPDATE_CENTER,
        "ci_jenkins_plugin_roots": sorted(roots),
        "ci_jenkins_plugins": [selected[k] for k in sorted(selected)],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jenkins-version", required=True)
    parser.add_argument("--metadata-file", help="Resolve from an already downloaded official catalog")
    args = parser.parse_args()
    if args.metadata_file:
        with open(args.metadata_file) as response:
            metadata = json.load(response)
    else:
        with urllib.request.urlopen(UPDATE_CENTER, timeout=120) as response:
            metadata = json.load(response)
    lock = resolve(metadata, args.jenkins_version, ROOTS)
    print(json.dumps(lock, indent=2))


if __name__ == '__main__':
    main()
