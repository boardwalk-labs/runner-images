# Image policy — versioning, vulnerabilities, deprecation

## Versioning

- Images version with **semver tags** (`v1.4.0` → `ghcr.io/boardwalk-labs/boardwalk-runner-linux:1.4.0`).
- Every published image has an **immutable digest**; the Boardwalk platform (and anyone serious)
  references images **by digest**, never by tag. `latest` is never published.
- **Major:** removed/replaced tools, default-user or filesystem-contract changes. **Minor:** added
  tools, parent-image digest bumps, tool upgrades. **Patch:** security-only rebuilds.
- Everything is pinned: the parent image by digest, each explicitly-installed tool by version
  (`ARG`s at the top of the Dockerfile). An upgrade is a one-line reviewed diff, visible in the
  release notes.

## SBOM and provenance

Every release publishes, together: the image (by digest), its SBOM (SPDX, generated at build),
and build provenance. CI regenerates the SBOM on every PR and posts the diff, so "what changed
in the environment" is answerable from the PR alone.

## Vulnerability policy

- Every PR and every release is scanned; the scan report publishes with the release.
- **Gate:** new *critical* findings block merge/release. *High* findings block release unless
  triaged below.
- **Triage:** a finding may be accepted with an entry in `SECURITY_TRIAGE.md` stating the CVE,
  why it doesn't apply (not reachable / no fixed version upstream / mitigated by the runner
  sandbox), and a revisit date. Untriaged highs don't ship.
- Security-only patch releases rebuild on the latest parent digest and ship as `x.y.z+1`.

## Deprecation

- Deprecating an image or major version is announced in release notes **with a sunset date ≥90
  days out**.
- Deprecated digests keep working until sunset (immutability is the point); after sunset they
  stop receiving security rebuilds and hosted scheduling may refuse them.
- Tool *removals* only happen in majors, listed prominently in the release notes.
