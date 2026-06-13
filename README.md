# runner-images

Base image definitions for [Boardwalk](https://boardwalk.sh) hosted runners — the environment
your workflow programs and shell steps execute in. Image sources, pinned versions, SBOMs, scan
reports, and the versioning policy are all here and reproducible.

The hosted Boardwalk platform builds its worker images from these bases, pinned by digest, then
adds a private runtime layer. That layer is not published, but it carries no secrets-relevant
behavior (see the platform security docs); the base images in this repo define what your code
sees at runtime, and you can build and inspect them yourself.

## Images

| Label | Image | Docs |
| --- | --- | --- |
| `boardwalk/linux` | `ghcr.io/boardwalk-labs/boardwalk-runner-linux:<version>` | [docs/linux.md](./docs/linux.md) |

Planned variants: `boardwalk/linux-node`, `boardwalk/linux-python` (ecosystem toolchains),
`boardwalk/linux-large` (same image, larger resources).

## Build and inspect locally

```sh
docker build -t boardwalk-runner-linux images/linux
docker run --rm -it boardwalk-runner-linux bash    # inspect the runtime environment

# Regenerate the committed environment lock after any image change (CI fails on drift):
scripts/env-manifest.sh boardwalk-runner-linux > images/linux/ENVIRONMENT.lock
```

`images/linux/ENVIRONMENT.lock` is the human-reviewable list of pinned OS packages and tools; CI
re-derives it on every PR and fails if it drifts, so an environment change lands as a reviewed diff.
Every release publishes the image digest, an SPDX SBOM, and the vulnerability scan report.
Versioning, scan gates, triage, and deprecation windows are documented in
[POLICY.md](./POLICY.md) and [SECURITY_TRIAGE.md](./SECURITY_TRIAGE.md).

## What this repo is not

- Not the engine ([`boardwalk`](https://github.com/boardwalk-labs/boardwalk)) — that runs the
  control plane on your hardware.
- Not the self-hosted runner client ([`runner`](https://github.com/boardwalk-labs/runner))
  — that executes Boardwalk-scheduled runs on your machines (and can use these images too).

## License

Apache-2.0
