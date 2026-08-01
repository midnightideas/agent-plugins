FROM mcr.microsoft.com/devcontainers/base:ubuntu

# non-interactive apt operations
ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# base runtime packages
# ---------------------------------------------------------------------------
# install a small set of non‑graphical tools required by the devcontainer
# image (socat added for port forwarding use cases). combine the bubblewrap
# setuid step with the install to avoid an extra layer.
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  wget gnupg curl ca-certificates \
  bubblewrap jq libcap2-bin \
  git-secret gpg gpg-agent \
  socat && \
  # bubblewrap is now installed; make it setuid so it can create namespace
  # sandboxes on hosts where user namespaces are restricted (the devcontainer
  # base image ships with bubblewrap).
  bwrap_path="$(command -v bwrap)" && \
  echo "Making bubblewrap setuid root (devcontainer)" && \
  chown root:root "$bwrap_path" && chmod 4755 "$bwrap_path" && \
  rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# nodejs + sandbox-runtime (need when running sandboxed tools)
# ---------------------------------------------------------------------------
# install Node.js from the NodeSource LTS repo and the globe‑installed
# sandbox-runtime package, then export its seccomp BPF profiles.  perform all
# steps in one RUN to keep the image smaller.
RUN set -eux; \
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -; \
  apt-get update; \
  apt-get install -y --no-install-recommends nodejs; \
  npm install -g @anthropic-ai/sandbox-runtime; \
  npm cache clean --force; \
  rm -rf /var/lib/apt/lists/*; \
  mkdir -p /usr/local/share/sandbox-runtime/seccomp; \
  npm_root="$(npm root -g)"; \
  src="$npm_root/@anthropic-ai/sandbox-runtime/vendor/seccomp"; \
  test -d "$src"; \
  cp -a "$src/." /usr/local/share/sandbox-runtime/seccomp/; \
  chmod -R a+rX /usr/local/share/sandbox-runtime/seccomp;

# ---------------------------------------------------------------------------
# install linuxbrew + claude-code via brew for vscode user
# ---------------------------------------------------------------------------
RUN mkdir -p /home/linuxbrew/.linuxbrew && chown -R vscode:vscode /home/linuxbrew
ENV NONINTERACTIVE=1
USER vscode
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
  && /home/linuxbrew/.linuxbrew/bin/brew --version \
  && echo >> /home/vscode/.bashrc \
  && echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' >> /home/vscode/.bashrc \
  && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)" \
  && /home/linuxbrew/.linuxbrew/bin/brew install yq gh 1password-cli \
  && /home/linuxbrew/.linuxbrew/bin/brew install --cask claude-code
USER root

# ---------------------------------------------------------------------------
# helper scripts copied into place
# ---------------------------------------------------------------------------
COPY --chmod=755 postStartCommand.sh /usr/local/bin/postStartCommand.sh
COPY --chmod=755 bin/vscode-terminal-claude-code /usr/local/bin/vscode-terminal-claude-code
