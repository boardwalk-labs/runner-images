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
and build provenance. "What changed in the environment" is answerable from the PR alone two ways:
every PR regenerates the SBOM (uploaded as a build artifact), and a committed package-level
**environment lock** (`images/<image>/ENVIRONMENT.lock` — pinned OS packages + tools, produced by
`scripts/env-manifest.sh`) is **re-derived in CI and must match the built image**, so any change to
the environment fails the build until it's regenerated and committed — landing the diff in the PR's
own files for review.

## Vulnerability policy

- Every PR and every release is scanned; the scan report publishes with the release.
- **Gate:** a new *fixable* **critical** finding blocks merge/release. Clear it by bumping the
  parent digest or the pinned tool (then regenerate `ENVIRONMENT.lock`).
- **High findings** are reported on every run (an informational scan step) and **triaged** in
  `SECURITY_TRIAGE.md`, but don't hard-block: the npm toolchain's vendored deps carry fixable highs
  that lag upstream and aren't reachable in the runner threat model. Hard-gating them would break CI
  on upstream lag, not on real exposure.
- **Won't-fix findings** (no upstream fixed version, e.g. some Debian-base CVEs) are excluded by the
  scanner's `--only-fixed` and the notable ones are documented in `SECURITY_TRIAGE.md` so they stay
  visible.
- **Triage:** every entry in `SECURITY_TRIAGE.md` states the CVE, why it's accepted (not reachable /
  no upstream fix / mitigated by the sandbox), and a revisit condition. Making a *fixable critical*
  non-blocking additionally requires an explicit, time-boxed scanner ignore rule.
- Security-only patch releases rebuild on the latest parent digest and ship as `x.y.z+1`.

## Deprecation

- Deprecating an image or major version is announced in release notes **with a sunset date ≥90
  days out**.
- Deprecated digests keep working until sunset (immutability is the point); after sunset they
  stop receiving security rebuilds and hosted scheduling may refuse them.
- Tool *removals* only happen in majors, listed prominently in the release notes.
