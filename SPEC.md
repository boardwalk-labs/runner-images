# SPEC — `runner-images`

> The public trust surface for hosted runner environments: exactly what your code runs inside on hosted Boardwalk. Apache-2.0. Public in **Phase 3** (before hosted-runner trust questions arise).
>
> These public base images are what the Boardwalk platform worker images derive from **by digest** — so the build environment is inspectable without the private runtime layer being public.

## 1. Purpose

Anyone running workflows on hosted compute should be able to answer: what OS, what tools, what versions, what changed between releases, and what known vulnerabilities exist. This repo is that answer — image definitions, provenance, and policy, all public and reproducible.

## 2. Contents

- **Dockerfiles + build scripts** for every official hosted-runner base image.
- **Pinned versions** of OS packages and preinstalled tools; upgrades are explicit, reviewed diffs.
- **SBOM generation** per image build; published with each release.
- **Vulnerability scan output** per release, with a documented triage policy.
- **Release notes + deprecation policy** (images are versioned; digests are immutable; deprecations announced with a sunset window).
- **Docs per image:** installed tools, filesystem layout, default user and permissions, workspace behavior, resource limits, network/egress expectations, known tool-compatibility notes.

## 3. Images (initial)

| Image | Label | Contents |
|---|---|---|
| `ghcr.io/boardwalk-labs/boardwalk-runner-linux:<version>` | `boardwalk/linux` | Base Linux + Node LTS + git + common build tooling |
| Later: `-node`, `-python` variants | `boardwalk/linux-*` | Ecosystem-specific toolchains |

A larger machine is **not** a separate image: it's the `runs_on` `size` selector (`{ label, size }`), a per-run resource override on this same image, so nothing extra is published here.

Tagging: semver tags + immutable digests for every published image; `latest` is never used in hosted deployments.

## 4. CI

- Every PR: image builds reproducibly + an offline contract smoke test; the committed
  `ENVIRONMENT.lock` (pinned packages + tools) is re-derived and must match the built image — an
  environment change fails the build until it's regenerated and committed, so the diff is reviewed in
  the PR itself; the SBOM is regenerated as an artifact; the scanner gates fixable criticals and
  reports highs for triage (see POLICY.md / SECURITY_TRIAGE.md).
- Every release: push by digest, publish SBOM + scan report + release notes together.

## 5. Ready to go public when

1. The `boardwalk/linux` image builds, scans clean (per the triage policy), and publishes with SBOM + digest.
2. the Boardwalk platform's worker image consumes the published base **by digest**.
3. Image docs (§2) complete for every published image; publication checklist passes.
