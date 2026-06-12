# boardwalk-runner-images

The public trust surface for [Boardwalk](https://boardwalk.sh) hosted runners: **exactly what
your code runs inside.** Image definitions, pinned versions, SBOMs, scan reports, and policy —
all public, all reproducible.

The Boardwalk platform's worker images derive from these bases **by digest**. You can't see the platform's
private runtime layer (it holds no secrets-relevant behavior — see the security model in the
platform docs), but you can inspect every byte of the environment your programs and shell steps
execute in.

## Images

| Label | Image | Docs |
| --- | --- | --- |
| `boardwalk/linux` | `ghcr.io/boardwalk-dev/boardwalk-runner-linux:<version>` | [docs/linux.md](./docs/linux.md) |

Planned variants: `boardwalk/linux-node`, `boardwalk/linux-python` (ecosystem toolchains),
`boardwalk/linux-large` (same image, larger resources).

## Verify it yourself

```sh
docker build -t boardwalk-runner-linux images/linux
docker run --rm -it boardwalk-runner-linux bash    # poke around the exact environment
```

Every release publishes the image digest, an SPDX SBOM, and the vulnerability scan report
side by side. Versioning, scan gates, and deprecation windows: [POLICY.md](./POLICY.md).

## What this repo is not

- Not the engine ([`boardwalk`](https://github.com/boardwalk-dev/boardwalk)) — that runs the
  control plane on your hardware.
- Not the self-hosted runner client ([`boardwalk-runner`](https://github.com/boardwalk-dev/boardwalk-runner))
  — that executes Boardwalk-scheduled runs on your machines (and can use these images too).

## License

Apache-2.0
