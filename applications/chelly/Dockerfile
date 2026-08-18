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
    git-lfs \
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
    tzdata \
    ;

# GitHub CLI インストール
# api.github.com は未認証だと同一IPあたり60回/時のrate limitがあり、NAT配下だと
# 他者と枠を共有して403になるため、rate limitのないリリースページのリダイレクト先
# (https://github.com/cli/cli/releases/tag/vX.Y.Z) からバージョンを解決する。
# 一時的に解決できない場合は --build-arg=GH_VERSION=X.Y.Z で固定できる。
ARG GH_VERSION=""
RUN mkdir -p /tmp && chmod 0777 /tmp
WORKDIR /tmp
RUN set -eu; \
    if [ "${TARGETOS}" != "linux" ]; then \
        echo "Unsupported target OS: ${TARGETOS}" >&2; \
        exit 1; \
    fi; \
    case "${TARGETARCH}/${TARGETVARIANT}" in \
        386/|amd64/|arm64/|arm64/v8) gh_arch="${TARGETARCH}" ;; \
        arm/|arm/v6|arm/v7) gh_arch="armv6" ;; \
        *) \
            echo "Unsupported target architecture: ${TARGETARCH}/${TARGETVARIANT}" >&2; \
            exit 1; \
            ;; \
    esac; \
    if [ -n "${GH_VERSION}" ]; then \
        gh_version="${GH_VERSION}"; \
    else \
        gh_release_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
            https://github.com/cli/cli/releases/latest)"; \
        gh_version="${gh_release_url##*/tag/v}"; \
    fi; \
    case "${gh_version}" in \
        [0-9]*) ;; \
        *) echo "Failed to resolve gh version: ${gh_version}" >&2; exit 1 ;; \
    esac; \
    archive="gh_${gh_version}_linux_${gh_arch}.tar.gz"; \
    release_url="https://github.com/cli/cli/releases/download/v${gh_version}"; \
    curl -fsSLO "${release_url}/${archive}"; \
    curl -fsSLo gh_checksums.txt "${release_url}/gh_${gh_version}_checksums.txt"; \
    sha256sum --check --ignore-missing gh_checksums.txt; \
    tar -xzf "${archive}" --strip-components=2 -C /usr/local/bin \
        "gh_${gh_version}_linux_${gh_arch}/bin/gh"; \
    rm -f "/tmp/${archive}" /tmp/gh_checksums.txt

# Node.js インストール
# Debian の nodejs/npm パッケージは webpack など大量のビルドツールを引き込むため、
# npm 同梱の公式 tarball を使う。
ARG NODE_VERSION=""
RUN set -eu; \
    case "${TARGETARCH}/${TARGETVARIANT}" in \
        amd64/) node_arch="x64" ;; \
        arm64/|arm64/v8) node_arch="arm64" ;; \
        arm/v7) node_arch="armv7l" ;; \
        *) \
            echo "Unsupported target architecture: ${TARGETARCH}/${TARGETVARIANT}" >&2; \
            exit 1; \
            ;; \
    esac; \
    if [ -n "${NODE_VERSION}" ]; then \
        node_version="v${NODE_VERSION#v}"; \
    else \
        curl -fsSLo node_index.json https://nodejs.org/dist/index.json; \
        node_version="$(jq -r 'map(select(.lts != false)) | .[0].version' node_index.json)"; \
        rm -f /tmp/node_index.json; \
    fi; \
    case "${node_version}" in \
        v[0-9]*) ;; \
        *) echo "Failed to resolve Node.js version: ${node_version}" >&2; exit 1 ;; \
    esac; \
    archive="node-${node_version}-linux-${node_arch}.tar.xz"; \
    dist_url="https://nodejs.org/dist/${node_version}"; \
    curl -fsSLO "${dist_url}/${archive}"; \
    curl -fsSLo node_checksums.txt "${dist_url}/SHASUMS256.txt"; \
    sha256sum --check --ignore-missing node_checksums.txt; \
    tar -xJf "${archive}" --strip-components=1 -C /usr/local \
        --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md; \
    rm -f "/tmp/${archive}" /tmp/node_checksums.txt

# claude-agent-acp (ACP エージェント) インストール
# /nix は named volume で永続化しており、イメージ側の /nix が変わると volume ごと
# 破棄されるため、nix profile ではなく npm で /usr/local 配下に入れる。
ARG CLAUDE_AGENT_ACP_VERSION="latest"
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g "@agentclientprotocol/claude-agent-acp@${CLAUDE_AGENT_ACP_VERSION}"

# --------------------------------------------------------
# ユーザー作成と権限設定
# --------------------------------------------------------
RUN \
    if ! getent group "${GID}" > /dev/null; then \
        groupadd -g "${GID}" warashi; \
    fi && \
    useradd -l -m -u "${UID}" -g "${GID}" -G sudo -s /bin/bash warashi && \
    echo 'warashi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/warashi && \
    chmod 0440 /etc/sudoers.d/warashi

# rootless podman を入れ子で動かすための subuid/subgid 範囲を明示する。
# useradd はこの範囲を自動では作らず、無いと podman が single mapping にフォールバックして
# 複数 UID を使うイメージが壊れる。100000 起点なのは ARG UID/GID にどんな値が来ても
# 重ならないようにするため。
RUN echo 'warashi:100000:65536' > /etc/subuid && \
    echo 'warashi:100000:65536' > /etc/subgid

# podman-docker が docker 実行のたびに出す案内メッセージを抑止する
RUN mkdir -p /etc/containers && touch /etc/containers/nodocker

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
    git config --global core.untrackedcache false && \
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
