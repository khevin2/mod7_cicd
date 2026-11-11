# Jenkins build 4: image vulnerability gate blocked the build

Read-only inspection of `mod9-secure-ecs/4` on 2026-11-10 confirmed source revision `22fe52c4edb74d905db8bf520740dd528e90bd7b` reached image building after the source gates. The built image ID was `sha256:87452813b60f3dd381261419a57ed1f289439cf765b25269030c114f39012c43`.

Archived `trivy-image.json` reported these High-severity findings in Alpine 3.24.1:

| Finding | Package | Installed | Fixed minimum |
| --- | --- | --- | --- |
| CVE-2026-107891 | musl | 1.2.6-r2 | 1.2.6-r3 |
| CVE-2026-107891 | musl-utils | 1.2.6-r2 | 1.2.6-r3 |
| CVE-2026-85091 | zlib | 1.3.2-r0 | 1.3.2-r1 |

The image gate failed. Image secret scanning and SBOM generation were not reached; publication and deployment were skipped. No exclusions were added for these vulnerabilities.

The local Dockerfile now installs at least the fixed versions, alongside the existing OpenSSL updates. The pinned Node base digest is unchanged. Current Alpine repositories supplied `musl`/`musl-utils` 1.2.6-r3 and zlib 1.4-r0 during the local build; minimum-version constraints allow superseding security revisions. These package repositories remain a moving input to the build.

The patched local image built successfully and passed a runtime smoke check without host ports: `/health` returned `status=ok`, UID was 10001, and npm/npx were absent. The temporary smoke container was removed.

Vendor references: [Alpine musl advisory](https://security.alpinelinux.org/vuln/CVE-2026-107891), [Alpine zlib advisory](https://security.alpinelinux.org/vuln/CVE-2026-85091). A new Jenkins build must validate the patched source and archive its own image reports and SBOM before release.
