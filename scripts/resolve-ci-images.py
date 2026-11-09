#!/usr/bin/env python3
"""Read Docker Hub metadata and print immutable image pins as Ansible YAML.

Does not pull images, write files, or change cloud resources. Run explicitly
to select new image versions; keep the printed digests for subsequent runs.
"""
import json
import re
import urllib.parse
import urllib.request


def resolve(repository, tag):
    query = urllib.parse.urlencode({
        "service": "registry.docker.io", "scope": f"repository:library/{repository}:pull"
    })
    with urllib.request.urlopen(f"https://auth.docker.io/token?{query}", timeout=30) as response:
        token = json.load(response)["token"]
    request = urllib.request.Request(
        f"https://registry-1.docker.io/v2/library/{repository}/manifests/{tag}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": ", ".join([
                "application/vnd.oci.image.index.v1+json",
                "application/vnd.docker.distribution.manifest.list.v2+json",
                "application/vnd.oci.image.manifest.v1+json",
                "application/vnd.docker.distribution.manifest.v2+json",
            ]),
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        digest = response.headers["Docker-Content-Digest"]
    if not digest or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError(f"Registry returned no valid digest for {repository}:{tag}")
    return f"docker.io/library/{repository}@{digest}"


if __name__ == "__main__":
    # Resolve both before printing, so failure cannot produce a half-valid file.
    images = {"ci_sonar_image": resolve("sonarqube", "community"),
              "ci_postgres_image": resolve("postgres", "17-bookworm")}
    print("# Selected from sonarqube:community and postgres:17-bookworm; review before use.")
    for key, value in images.items():
        print(f'{key}: "{value}"')
