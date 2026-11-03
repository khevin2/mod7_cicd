#!/usr/bin/env python3
"""Render the ECS registration input to stdout without contacting AWS."""
import argparse
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--family", required=True)
    parser.add_argument("--image", required=True, help="ECR image URI pinned by sha256 digest")
    parser.add_argument("--execution-role-arn", required=True)
    parser.add_argument("--log-group", required=True)
    parser.add_argument("--region", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,255}", args.family):
        parser.error("invalid task family")
    if not re.fullmatch(r"[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/[a-z0-9._/-]+@sha256:[0-9a-f]{64}", args.image):
        parser.error("image must be a private ECR URI pinned to a sha256 digest")
    if not re.fullmatch(r"arn:aws(?:-[a-z]+)?:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+", args.execution_role_arn):
        parser.error("invalid execution role ARN")
    if not re.fullmatch(r"[a-z0-9-]+", args.region) or not re.fullmatch(r"[A-Za-z0-9_./#-]{1,512}", args.log_group):
        parser.error("invalid region or log group")
    if f".ecr.{args.region}.amazonaws.com/" not in args.image:
        parser.error("image region must match the log region")
    values = {
        "family": args.family,
        "image": args.image,
        "execution_role_arn": args.execution_role_arn,
        "log_group": args.log_group,
        "region": args.region,
    }
    template = (Path(__file__).resolve().parent.parent / "ecs/task-definition.json.tftpl").read_text()
    rendered = re.sub(r"\$\{jsonencode\(([a-z_]+)\)\}", lambda match: json.dumps(values[match.group(1)]), template)
    task = json.loads(rendered)
    print(json.dumps(task, indent=2))


if __name__ == "__main__":
    main()
