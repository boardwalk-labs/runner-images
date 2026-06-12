# Contributing to runner-images

This repo is a trust surface, so contributions are judged on auditability as much as utility.

## Ground rules

- **Everything is pinned.** Parent images by digest, tools by version (`ARG`s at the top of the
  Dockerfile). A PR that introduces an unpinned `latest`, a floating apt repo, or a `curl | sh`
  will be rejected regardless of how useful the tool is.
- **Small surface beats convenient surface.** Every added package is attack surface, SBOM noise,
  and scan burden forever. The bar for adding a tool to `boardwalk/linux` is "a meaningful share
  of workflows shell out to it" — niche toolchains belong in ecosystem variants (`-node`,
  `-python`) or custom images.
- **Contract changes are majors.** The default user, `/workspace` semantics, and anything in
  docs/\*.md under "Filesystem layout" / "User and permissions" are product contract
  (POLICY.md).
- **Docs move with the diff.** A tool added/removed/bumped updates the image's docs table in the
  same PR.

## Workflow

```sh
docker build -t boardwalk-runner-linux images/linux
docker run --rm boardwalk-runner-linux bash -c 'node --version && gh --version'
```

CI builds the image, smoke-tests the environment contract, generates the SBOM (the diff shows
in the PR), and gates on new critical vulnerabilities. See [POLICY.md](./POLICY.md) for the
triage path when a finding doesn't apply.

## Reporting

Bugs and proposals via GitHub issues. Security reports: see [SECURITY.md](./SECURITY.md) —
never a public issue.
