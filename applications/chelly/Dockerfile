FROM debian:stable

ARG UID=1000
ARG GID=1000
ARG TARGETOS TARGETARCH TARGETVARIANT

# --------------------------------------------------------
# パッケージインストール
# --------------------------------------------------------
# aptのキャッシュ用設定（キャッシュを削除しないように設定を変更）
RUN rm -f /etc/apt/apt.conf.d/docker-clean; \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# apt-get update と install を1レイヤーにまとめ、--mount=type=cache を利用
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    sudo \
    curl \
    git \
    less \
    openssh-client \
    bash \
    jq \
    xz-utils \
    podman-docker \
    uidmap \
    passt \
    slirp4netns \
    fuse-overlayfs \
    aardvark-dns \
    catatonit \
    nftables \
    locales \
    ncurses-term \
    ;

# GitHub CLI インストール
RUN mkdir -p /tmp && chmod 0777 /tmp
WORKDIR /tmp
ADD https://api.github.com/repos/cli/cli/releases/latest /tmp/gh-release.json
RUN set -eu; \
    if [ "${TARGETOS}" != "linux" ]; then \
        echo "Unsupported target OS: ${TARGETOS}" >&2; \
        exit 1; \
    fi; \
    case "${TARGETARCH}/${TARGETVARIANT}" in \
        386/|amd64/|arm64/) gh_arch="${TARGETARCH}" ;; \
        arm/|arm/v6|arm/v7) gh_arch="armv6" ;; \
        *) \
            echo "Unsupported target architecture: ${TARGETARCH}/${TARGETVARIANT}" >&2; \
            exit 1; \
            ;; \
    esac; \
    gh_version="$(jq -r '.tag_name | ltrimstr("v")' /tmp/gh-release.json)"; \
    archive="gh_${gh_version}_linux_${gh_arch}.tar.gz"; \
    release_url="https://github.com/cli/cli/releases/download/v${gh_version}"; \
    curl -fsSLO "${release_url}/${archive}"; \
    curl -fsSLo gh_checksums.txt "${release_url}/gh_${gh_version}_checksums.txt"; \
    sha256sum --check --ignore-missing gh_checksums.txt; \
    tar -xzf "${archive}" --strip-components=2 -C /usr/local/bin \
        "gh_${gh_version}_linux_${gh_arch}/bin/gh"; \
    rm -f /tmp/gh-release.json "/tmp/${archive}" /tmp/gh_checksums.txt

# --------------------------------------------------------
# ユーザー作成と権限設定
# --------------------------------------------------------
RUN groupadd -g "${GID}" warashi && \
    useradd -l -m -u "${UID}" -g warashi -G sudo -s /bin/bash warashi && \
    echo 'warashi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/warashi && \
    chmod 0440 /etc/sudoers.d/warashi

USER warashi
ENV USER=warashi
WORKDIR /home/warashi

ENV \
    CLAUDE_CONFIG_DIR=/home/warashi/.claude \
    LANG=C.UTF-8 \
    PATH="/home/warashi/.nix-profile/bin:/home/warashi/.local/bin:${PATH}" \
    TZ=Asia/Tokyo

# --------------------------------------------------------
# Git・Claude・Copilot・Nixの設定
# --------------------------------------------------------
# Git初期設定
RUN mkdir -p /home/warashi/.config/git && \
    git config --global user.name 'Shinnosuke Sawada-Dazai' && \
    git config --global user.email '3600530+Warashi@users.noreply.github.com'

# Claude CLI インストール
ADD --chmod=0666 https://claude.ai/install.sh /tmp/claude-install.sh
RUN bash /tmp/claude-install.sh && rm -f /tmp/claude-install.sh

# Copilot CLI インストール
ADD --chmod=0666 https://gh.io/copilot-install /tmp/copilot-install.sh
RUN bash /tmp/copilot-install.sh && rm -f /tmp/copilot-install.sh

# Nix インストール（single user install）
ADD --chmod=0666 https://nixos.org/nix/install /tmp/nix-install.sh
RUN sh /tmp/nix-install.sh --no-daemon --no-channel-add && \
    rm -f /tmp/nix-install.sh && \
    mkdir -p ~/.config/nix && \
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

COPY --chown=warashi --chmod=0755 <<'EOF' /home/warashi/.local/bin/chelly-entrypoint
#!/bin/sh

if [ -f flake.nix ]; then
  if [ "$#" -eq 0 ]; then
    exec nix develop --accept-flake-config
  fi
  exec nix develop --accept-flake-config --command "$@"
elif [ -f shell.nix ]; then
  if [ "$#" -eq 0 ]; then
    exec nix-shell
  fi
  exec nix-shell --run "$*"
else
  exec "$@"
fi
EOF

ENTRYPOINT ["/home/warashi/.local/bin/chelly-entrypoint"]
