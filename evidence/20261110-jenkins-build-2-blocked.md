# Jenkins build 2: configuration gate blocked the build

Read-only SSH inspection of the operator-started `mod9-secure-ecs/2` console and archived Trivy report on 2026-11-10 found:

- Snyk tested 369 dependencies and reported zero issues at the configured High/Critical threshold after the Jest upgrade.
- Trivy repository vulnerability scanning completed and the pipeline proceeded to misconfiguration scanning.
- Trivy misconfiguration scanning returned nine High/Critical findings: three dynamic-destination egress instances, three subnet automatic-public-IP instances, missing ALB invalid-header rejection, intentional public ALB exposure, and an HTTP listener.
- The configuration scan failed; image build, image scan/SBOM, publication and deployment were skipped. Final result: `FAILURE`.

Local follow-up enables invalid-header rejection and replaces subnet-wide automatic public IP assignment with explicit host configuration. Dynamic-destination egress and intentional public ALB exposure have resource-specific, documented exceptions expiring 2026-12-10. On 2026-11-10 the operator approved demo HTTP; a separate exception for the named HTTP listener expires on the same date and is restricted to the sample application and approved client CIDRs. Vulnerability and secret gates remain unchanged.

Both modified Terraform stacks passed local `terraform validate`. These source edits have not been applied to AWS by the assistant. A passing configuration scan will not prove that unapplied Terraform settings exist in the live account.

After the HTTP decision, pinned Trivy `0.73.0` (image digest `sha256:7cced7cae583819fc7806d4cbc0dbbc7cad18b99f7d3e235192e6da8c091045c`) scanned a disposable copy of publishable source using the pipeline's High/Critical misconfiguration flags. It detected 12 configuration files and exited `0`; the resource-local exception annotations were recognized. Ignored private inputs and generated Terraform state/plan snapshots were not copied. Terraform formatting and `git diff --check` passed. A new Jenkins run is still required to validate the corrected source in the integrated pipeline.
