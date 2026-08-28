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
# /nix は named volume で覆われるためイメージ側の /nix は実行時に見えない。
# nix profile に入れてもイメージ再ビルド時に volume 側と食い違うため、npm で
# /usr/local 配下に入れる。
ARG CLAUDE_AGENT_ACP_VERSION="latest"
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g "@agentclientprotocol/claude-agent-acp@${CLAUDE_AGENT_ACP_VERSION}"

# pi coding agent CLI インストール
# claude-agent-acp と同じ理由で npm から /usr/local 配下に入れる。
ARG PI_VERSION="latest"
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g "@earendil-works/pi-coding-agent@${PI_VERSION}"

# pi-acp (pi の ACP アダプタ) インストール
# pi 本体は ACP を話さないため、agent-shell から使うにはこのアダプタが要る。
# 隣と違って latest にしないのは、0.0.x で README が breaking change を予告して
# いるため。イメージ再ビルドのたびに agent-shell 側が壊れるのを避ける。
ARG PI_ACP_VERSION="0.0.33"
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g "pi-acp@${PI_ACP_VERSION}"

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

# --------------------------------------------------------
# Nix インストーラの同梱
# --------------------------------------------------------
# /nix は named volume で永続化されるため、実行時にはイメージ側の /nix が隠れる。
# ビルド時に nix を /nix へ入れると、profile の実体 (~/.local/state/nix 配下にあり
# イメージレイヤーに残る) が新しい store path を指す一方で volume には古い store しか
# 無い状態になり nix が消えるため、イメージにはインストーラだけを置き、実際の導入は
# entrypoint が volume に対して行う。
# ADD で取得しているのは、install スクリプトの更新でレイヤーキャッシュを失効させ、
# 再ビルド時に nix のバージョンを追随させるため。
ADD --chmod=0666 https://nixos.org/nix/install /tmp/nix-install.sh
RUN set -eu; \
    case "${TARGETARCH}/${TARGETVARIANT}" in \
        386/) nix_system="i686-linux" ;; \
        amd64/) nix_system="x86_64-linux" ;; \
        arm64/|arm64/v8) nix_system="aarch64-linux" ;; \
        arm/v6) nix_system="armv6l-linux" ;; \
        arm/|arm/v7) nix_system="armv7l-linux" ;; \
        *) \
            echo "Unsupported target architecture: ${TARGETARCH}/${TARGETVARIANT}" >&2; \
            exit 1; \
            ;; \
    esac; \
    nix_release="$(awk -v target="${nix_system}" \
        '/hash=/ { hash = $0 } \
         index($0, "-" target ".tar.xz") { \
             sub(/.*hash=/, "", hash); archive = $0; sub(/.*\//, "", archive); \
             print hash, archive; exit \
         }' /tmp/nix-install.sh)"; \
    nix_hash="${nix_release% *}"; \
    archive="${nix_release#* }"; \
    case "${nix_hash}/${archive}" in \
        [0-9a-f][0-9a-f]*/nix-[0-9]*.tar.xz) ;; \
        *) echo "Failed to resolve Nix release for ${nix_system}" >&2; exit 1 ;; \
    esac; \
    nix_version="${archive#nix-}"; \
    nix_version="${nix_version%"-${nix_system}.tar.xz"}"; \
    curl -fsSLo "/tmp/${archive}" \
        "https://releases.nixos.org/nix/nix-${nix_version}/${archive}"; \
    echo "${nix_hash}  /tmp/${archive}" > /tmp/nix_checksums.txt; \
    sha256sum --check /tmp/nix_checksums.txt; \
    mkdir -p /opt/nix-installer; \
    tar -xJf "/tmp/${archive}" --strip-components=1 -C /opt/nix-installer; \
    chown -R "${UID}:${GID}" /opt/nix-installer; \
    rm -f "/tmp/${archive}" /tmp/nix_checksums.txt /tmp/nix-install.sh

# 空の /nix を warashi 所有で用意する。新規 volume はマウント先の所有者を引き継ぐため、
# これが無いと root 所有の volume ができてインストーラが書き込めない。
RUN mkdir -p /nix && chmod 0755 /nix && chown "${UID}:${GID}" /nix

# --------------------------------------------------------
# コンテナ内の Claude 向けメモリ
# --------------------------------------------------------
# ~/.claude はホストから bind mount されてホスト側の Claude と共有されるため、
# コンテナ固有の前提はそこには書けない。Claude Code が enterprise policy memory として
# 読む /etc/claude-code/CLAUDE.md はイメージ側にしか無く、コンテナ内だけに効く。
# mount 先は下流の flake で追加・変更されうるため、具体的なパスは列挙せず確認方法だけを書く。
COPY --chmod=0644 <<'EOF' /etc/claude-code/CLAUDE.md
- この環境はコンテナであり、コンテナのファイルシステム自体は終了時に破棄される
- ただし mount されたディレクトリはホスト側の実体または volume であり、コンテナ終了後も残る
- 起動時の作業ディレクトリはホストと同一のパスで mount されている
- git worktree から起動した場合は、メインリポジトリ側のディレクトリも同一のパスで mount されている
- 実際に mount されているディレクトリは /proc/self/mountinfo で確認できる
EOF

# --------------------------------------------------------
# git worktree の破壊的操作を止める shim
# --------------------------------------------------------
# git worktree から起動すると .git 本体はマウントされるが他の worktree のディレクトリは
# コンテナ内に存在しない。この状態で prune / remove を実行すると、消えたように見える
# 他の worktree の登録ごと落としてしまうため、コンテナ内では実行させない。
# エイリアスでは組み込みサブコマンドを上書きできないので PATH 先頭の shim にしている。
# gc も worktree を prune するが gc.worktreePruneExpire=never で無効化できるため対象外。
COPY --chmod=0755 <<'EOF' /opt/chelly-shims/git
#!/usr/bin/env bash
set -eu

worktree_seen=0
args=("$@")
while [ "${#args[@]}" -gt 0 ]; do
    case "${args[0]}" in
    # 値を別の引数として取るグローバルオプションは、その値をサブコマンドと誤認しないよう飛ばす。
    -C | -c | --git-dir | --work-tree | --namespace | --exec-path | --super-prefix | --config-env)
        args=("${args[@]:2}")
        continue
        ;;
    -*)
        args=("${args[@]:1}")
        continue
        ;;
    worktree) worktree_seen=1 ;;
    prune | remove)
        if [ "${worktree_seen}" = 1 ]; then
            echo "chelly: git worktree ${args[0]} はコンテナ内では禁止されています" >&2
            echo "chelly: 他の worktree のディレクトリがコンテナ内に無いため、その登録まで消えます" >&2
            exit 1
        fi
        break
        ;;
    *) break ;;
    esac
    args=("${args[@]:1}")
done

# 自分自身を再帰的に呼ばないよう PATH から shim のディレクトリを外して実体を探す。
git_path=""
IFS=:
for dir in ${PATH}; do
    if [ "${dir}" != /opt/chelly-shims ] && [ -x "${dir}/git" ]; then
        git_path="${dir}/git"
        break
    fi
done
unset IFS

if [ -z "${git_path}" ]; then
    echo "chelly: git が見つかりません" >&2
    exit 127
fi

exec "${git_path}" "$@"
EOF

USER warashi
ENV USER=warashi
WORKDIR /home/warashi

ENV \
    CLAUDE_CONFIG_DIR=/home/warashi/.claude \
    LANG=C.UTF-8 \
    PATH="/opt/chelly-shims:/home/warashi/.nix-profile/bin:/home/warashi/.local/bin:${PATH}" \
    TZ=Asia/Tokyo

# named volume はマウント先がイメージに存在しないと初回作成時に root 所有になり書き込めなくなる
# （/nix と同じ理由）。USER 切替後なので mkdir 自体が warashi 所有で作られる。
RUN mkdir -p \
        /home/warashi/.cache/go-build \
        /home/warashi/.cache/nix \
        /home/warashi/go/pkg/mod

# --------------------------------------------------------
# Git・Claude・Copilot・Nixの設定
# --------------------------------------------------------
# Git初期設定
RUN mkdir -p /home/warashi/.config/git && \
    git config --global core.untrackedcache false && \
    git config --global gc.worktreePruneExpire never && \
    git config --global user.name 'Shinnosuke Sawada-Dazai' && \
    git config --global user.email '3600530+Warashi@users.noreply.github.com'

# Claude CLI インストール
ADD --chmod=0666 https://claude.ai/install.sh /tmp/claude-install.sh
RUN bash /tmp/claude-install.sh && rm -f /tmp/claude-install.sh

# Copilot CLI インストール
ADD --chmod=0666 https://gh.io/copilot-install /tmp/copilot-install.sh
RUN bash /tmp/copilot-install.sh && rm -f /tmp/copilot-install.sh

# Nix 設定（インストール自体は entrypoint が volume 側の /nix に対して行う）
RUN mkdir -p ~/.config/nix && \
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# shell.nix から unfree パッケージを使えるようにする
RUN mkdir -p ~/.config/nixpkgs && \
    echo "{ allowUnfree = true; }" > ~/.config/nixpkgs/config.nix

COPY --chown=warashi --chmod=0755 <<'EOF' /home/warashi/.local/bin/chelly-entrypoint
#!/bin/sh

# nix の profile 実体は home 側にあってコンテナごとに消えるため、インストーラは実質
# 毎回走る。store は /nix の named volume に残っているので、追加されるのは差分だけ。
# flock で直列化しているのは、volume を共有する複数コンテナが同時に起動したときに
# 同じ store へ並行に書き込ませないため。判定をロックの外に出すと、待たされた側が
# 古い判定結果のまま走ってしまうので、判定ごとロック内に入れている。
# 出力を溜めて失敗時だけ stderr へ流すのは、成功時に進捗表示で画面を汚さず、かつ
# stdout でプロトコルを話す ACP エージェントへ何も漏らさないため。
if ! chelly_nix_install_log="$(flock /nix/.chelly-install.lock sh -c '
    nix --version >/dev/null 2>&1 ||
      /opt/nix-installer/install --no-daemon --no-channel-add --no-modify-profile
  ' 2>&1)"; then
  printf '%s\n' "${chelly_nix_install_log}" >&2
  exit 1
fi

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
