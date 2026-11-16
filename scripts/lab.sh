#!/usr/bin/env bash
# Use the Python from the activated Ansible controller environment.
set -Eeuo pipefail
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/lab.py" "$@"
