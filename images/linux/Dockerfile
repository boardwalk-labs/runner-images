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

# OS packages: the userland workflow shell steps actually reach for. --no-install-recommends +
# a cleaned apt cache keep the surface (and the SBOM) small.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  git \
  jq \
  openssh-client \
  python3 \
  python3-pip \
  python3-venv \
  tar \
  unzip \
  xz-utils \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI — pinned release artifact (no third-party apt repo in the trust surface).
RUN arch="$(dpkg --print-architecture)" \
  && curl -fsSL -o /tmp/gh.deb \
  "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.deb" \
  && dpkg -i /tmp/gh.deb \
  && rm /tmp/gh.deb \
  && gh --version

# JS toolchain: pnpm + tsx, installed into the image's global npm prefix. Deliberately NOT via
# corepack — corepack resolves through per-$HOME state and will download an unpinned version at
# run time (runs set HOME=/workspace), which breaks both pinning and offline runs.
RUN npm install -g "pnpm@${PNPM_VERSION}" "tsx@${TSX_VERSION}" \
  && pnpm --version && tsx --version

# /workspace is the per-run working directory contract: writable by the default user, HOME and
# cwd for hosted runs. The engine/worker layer above this image owns hydration + persistence.
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace

# Runs as the unprivileged `node` user (uid 1000). Derived images may switch to root for their
# own layer but MUST return to a non-root user.
USER node
ENV HOME=/workspace

CMD ["bash"]
