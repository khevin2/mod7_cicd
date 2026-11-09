#!/usr/bin/env python3
"""Generate a conservative, offline review list; never perform AWS actions."""
import argparse
import json
import re
import sys
from collections import defaultdict

ARN = re.compile(r'^arn:[^:]+:ecs:[^:]+:\d{12}:task-definition/([^/:]+):(\d+)$')


def review(data, keep):
    if keep < 1:
        raise ValueError('keep must be at least 1')
    for key in ('definitions', 'service_revisions', 'task_revisions', 'rollback_revisions'):
        if not isinstance(data.get(key), list):
            raise ValueError(f'{key} must be an array')
    if not data['definitions'] or not data['service_revisions'] or not data['rollback_revisions']:
        raise ValueError('definitions, service_revisions and rollback_revisions must be nonempty')
    definitions = {}
    families = defaultdict(list)
    for item in data['definitions']:
        if not isinstance(item, dict):
            raise ValueError('each definition must be an object')
        arn, status = item.get('arn'), item.get('status')
        match = ARN.fullmatch(arn) if isinstance(arn, str) else None
        if not match or status not in ('ACTIVE', 'INACTIVE') or arn in definitions:
            raise ValueError('invalid or duplicate definition ARN/status')
        definitions[arn] = status
        if status == 'ACTIVE':
            families[match.group(1)].append((int(match.group(2)), arn))
    protected = set()
    for key in ('service_revisions', 'task_revisions', 'rollback_revisions'):
        for arn in data[key]:
            if not isinstance(arn, str) or arn not in definitions or definitions[arn] != 'ACTIVE':
                raise ValueError(f'{key} contains an unknown or inactive revision')
            protected.add(arn)
    # Never recommend the newest revisions, even if no service currently uses them.
    for revisions in families.values():
        protected.update(arn for _, arn in sorted(revisions, reverse=True)[:keep])
    return {
        'mode': 'review-only; no AWS calls or changes',
        'protected_active_revisions': sorted(protected),
        'revisions_for_manual_review': sorted(arn for arn, status in definitions.items()
                                               if status == 'ACTIVE' and arn not in protected),
        'image_deletion_candidates': [],
        'limitations': ['Input completeness and freshness are not verified.',
                        'Recheck all consumers immediately before any separately approved cleanup.',
                        'No images are recommended for deletion, including untagged manifest children.'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', help='JSON snapshot; see docs/PHASE_8_9_RUNBOOK.md')
    parser.add_argument('--keep', type=int, default=3, help='minimum newest active revisions per family (default: 3)')
    args = parser.parse_args()
    try:
        with open(args.snapshot, encoding='utf-8') as file:
            result = review(json.load(file), args.keep)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, TypeError, AttributeError) as exc:
        print(f'Cannot review snapshot: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
