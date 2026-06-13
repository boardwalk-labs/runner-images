# Security triage

Findings the scanner reports that ship anyway, each with a reason and a revisit condition. The
machine-enforced gate is in [`.github/workflows/ci.yml`](./.github/workflows/ci.yml); the policy is
in [`POLICY.md`](./POLICY.md). The rule: **fixable criticals block the build.** Everything below is
either not fixable here or a fixable *high* whose risk doesn't warrant blocking the base image — but
nothing is invisible, and every entry has a revisit condition.

## What the gate enforces

- **Fixable critical → blocks.** A new critical CVE with an upstream fix fails CI; clear it by
  bumping the base digest or the pinned tool, then regenerate `images/linux/ENVIRONMENT.lock`.
- **Fixable high → reported, not blocked.** Surfaced every run by the informational scan step and
  triaged here. The toolchain churns faster than a base image should rebuild; a hard high-gate would
  break CI on upstream lag, not on real exposure.
- **Won't-fix (no upstream patch) → excluded** by `--only-fixed`. The notable ones are recorded
  below so they're not silently dropped.

## Standing exceptions

### Debian base — won't-fix (no fixed version)

The `node:24-bookworm-slim` parent carries CVEs Debian has marked "won't fix" for bookworm. They
have no fixed version, so `--only-fixed` excludes them and they can't be resolved in this repo.

| Package | CVE | Note |
|---|---|---|
| gh (GitHub CLI deps) | CVE-2024-52308 | Debian "won't fix"; no fixed version for bookworm. |
| sqlite3 (libsqlite) | CVE-2025-7458 | Debian "won't fix". Revisit on a parent-digest bump that ships a fix. |
| python3 | CVE-2026-7210 | Debian "won't fix". Revisit on a parent-digest bump that ships a fix. |

**Revisit:** each parent-image digest bump (a Minor per POLICY) — re-scan; drop any entry the new
base fixes.

### npm toolchain — fixable highs in vendored deps

The globally installed `pnpm` and `tsx` bundle their own dependency trees (`minimatch`, `tar`,
`brace-expansion`, `picomatch`, `ip-address`, `in-toto-golang`, and `pnpm` itself). The scanner
reports fixable highs there (mostly ReDoS / path-handling, EPSS < 0.1%). They are:

- **Not reachable in the runner threat model** — these are build-tool internals, not invoked on
  untrusted input during a run; the run's own dependencies are installed per-run into `/workspace`,
  outside this image.
- **Cleared by a version bump, not a patch here** — they resolve when `PNPM_VERSION` / `TSX_VERSION`
  are bumped in the Dockerfile (and `ENVIRONMENT.lock` regenerated).

**Revisit:** every `pnpm` / `tsx` version bump, and any time a finding's EPSS or reachability
changes materially. Accepted as non-blocking until then.

## Adding an exception

Prefer fixing (bump the base/tool). Accept a finding only with: the CVE id, why it doesn't apply
here (not reachable / no upstream fix / mitigated by the runner sandbox), and a revisit condition.
To make a *fixable critical* non-blocking you must also add an explicit `grype` ignore rule — keep
that rare and time-boxed.
