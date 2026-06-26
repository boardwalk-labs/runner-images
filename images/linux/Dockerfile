# SPDX-License-Identifier: Apache-2.0

# boardwalk/linux — the default hosted-runner base image.
#
# This is the public trust surface: exactly the environment a workflow program (and anything it
# shells out to) runs inside on Boardwalk's hosted `boardwalk/linux` runners. The Boardwalk
# platform's private worker layer derives FROM this image by digest; nothing in this file is
# platform-specific.
#
# Pinning policy (see ../../POLICY.md): the parent image is pinned by digest, every tool by
# version. Upgrades are explicit, reviewed diffs — never `latest`.

FROM node:24-bookworm-slim@sha256:2c87ef9bd3c6a3bd4b472b4bec2ce9d16354b0c574f736c476489d09f560a203

ARG GH_VERSION=2.94.0
ARG PNPM_VERSION=10.23.0
ARG TSX_VERSION=4.22.4
ARG TYPESCRIPT_VERSION=5.9.3
# The TypeScript language server powers the agent's LSP diagnostics (`typescript-language-server --stdio`).
ARG TS_LANGUAGE_SERVER_VERSION=5.3.0
# ripgrep: the fast recursive search coding agents (and the engine) lean on. uv: the fast Python
# package installer / runner. Both pulled as pinned release tarballs (no third-party apt repo).
ARG RIPGREP_VERSION=15.1.0
ARG UV_VERSION=0.11.24

# A UTF-8 locale by default: without it LANG is empty and git, Python, and many CLIs fall back to an
# ASCII codec and mangle non-ASCII I/O. C.UTF-8 needs no `locales` package on Debian.
ENV LANG=C.UTF-8

# OS packages: the userland workflow shell steps actually reach for, plus a C/C++ toolchain
# (build-essential + python3-dev) so `npm install` of native modules and `pip install` of packages
# with C extensions can compile instead of failing with "make: not found". --no-install-recommends +
# a cleaned apt cache keep the surface (and the SBOM) small. (git-lfs is intentionally NOT here: the
# Debian package is built with an ancient Go that fails the fixable-critical CVE gate; re-add it as a
# pinned upstream binary built with current Go, like gh/rg/uv, if LFS support is needed.)
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  bash \
  build-essential \
  ca-certificates \
  curl \
  file \
  git \
  jq \
  less \
  openssh-client \
  procps \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  rsync \
  tar \
  unzip \
  wget \
  xz-utils \
  zip \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI — pinned release artifact (no third-party apt repo in the trust surface).
RUN arch="$(dpkg --print-architecture)" \
  && curl -fsSL -o /tmp/gh.deb \
  "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.deb" \
  && dpkg -i /tmp/gh.deb \
  && rm /tmp/gh.deb \
  && gh --version

# ripgrep + uv — pinned release tarballs, arch-mapped from the dpkg arch to each project's target
# triple (the image index is multi-arch: linux/amd64 + linux/arm64). Binaries land in /usr/local/bin
# (root-owned, like gh), so the unprivileged runtime user can't overwrite its own toolchain.
RUN arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
       amd64) rg_target=x86_64-unknown-linux-musl; uv_target=x86_64-unknown-linux-gnu ;; \
       arm64) rg_target=aarch64-unknown-linux-gnu; uv_target=aarch64-unknown-linux-gnu ;; \
       *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
     esac \
  && curl -fsSL -o /tmp/rg.tar.gz \
     "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${rg_target}.tar.gz" \
  && tar -xzf /tmp/rg.tar.gz -C /tmp \
  && install -m 0755 "/tmp/ripgrep-${RIPGREP_VERSION}-${rg_target}/rg" /usr/local/bin/rg \
  && curl -fsSL -o /tmp/uv.tar.gz \
     "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${uv_target}.tar.gz" \
  && tar -xzf /tmp/uv.tar.gz -C /tmp \
  && install -m 0755 "/tmp/uv-${uv_target}/uv" /usr/local/bin/uv \
  && install -m 0755 "/tmp/uv-${uv_target}/uvx" /usr/local/bin/uvx \
  && rm -rf /tmp/rg.tar.gz /tmp/uv.tar.gz "/tmp/ripgrep-${RIPGREP_VERSION}-${rg_target}" "/tmp/uv-${uv_target}" \
  && rg --version && uv --version

# A single node-owned global npm prefix. The default prefix is /usr/local (root-owned), so a workflow
# running as the unprivileged `node` user can't `npm install -g` at runtime without EACCES. Point the
# prefix at a dedicated node-owned dir instead: the baked CLIs below install here, and a run can add
# its own globals to the same place. It's HOME-independent (HOME=/workspace is re-hydrated per run, so
# a $HOME-based prefix wouldn't survive), while node/npm and the system binaries stay root-owned.
# ENV PATH covers non-login shells and processes the worker spawns directly; the profile.d entry
# (below) covers login shells, where Debian's /etc/profile resets PATH and would otherwise drop it.
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/usr/local/share/npm-global/bin:$PATH

# JS toolchain: pnpm + tsx + the TypeScript compiler and language server, installed into the global
# npm prefix above. typescript-language-server (with a global tsserver via typescript) gives the
# agent LSP diagnostics for any workspace, even one without its own TypeScript install. Deliberately
# NOT via corepack — corepack resolves through per-$HOME state and will download an unpinned version
# at run time (runs set HOME=/workspace), which breaks both pinning and offline runs.
RUN mkdir -p /usr/local/share/npm-global \
  && printf 'export PATH=/usr/local/share/npm-global/bin:$PATH\n' > /etc/profile.d/npm-global.sh \
  && npm install -g "pnpm@${PNPM_VERSION}" "tsx@${TSX_VERSION}" \
  "typescript@${TYPESCRIPT_VERSION}" "typescript-language-server@${TS_LANGUAGE_SERVER_VERSION}" \
  && pnpm --version && tsx --version && tsc --version && typescript-language-server --version \
  && chown -R node:node /usr/local/share/npm-global

# /workspace is the per-run working directory contract: writable by the default user, HOME and
# cwd for hosted runs. The engine/worker layer above this image owns hydration + persistence.
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace

# Runs as the unprivileged `node` user (uid 1000). Derived images may switch to root for their
# own layer but MUST return to a non-root user.
USER node
ENV HOME=/workspace

CMD ["bash"]
