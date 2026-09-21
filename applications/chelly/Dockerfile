FROM docker.io/library/debian:stable

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
    podman-compose \
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
# /nix は実行時に named volume かホストの store で覆われ、イメージ側の /nix は見えない。
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
# インストーラを使うのは /nix を named volume に持つ構成のとき。ホストの store を
# read-only で共有する構成では nix はホストから渡され、インストーラは走らない。
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
# コンテナ内の agent 向けメモリ
# --------------------------------------------------------
# ~/.claude と ~/.copilot はホストと共有されるため、コンテナ固有の前提はイメージ側に置く。
# Claude の policy memory と Copilot の追加 instruction directory から同じ内容を読む。
# mount 先は下流の flake で追加・変更されうるため、具体的なパスは列挙せず確認方法だけを書く。
# ディレクトリを先に作るのは、BuildKit (apple/container) が COPY で自動作成する親ディレクトリ
# にも --chmod を適用して 0644 のディレクトリを作る一方、buildah (podman) は記号モードの
# --chmod を解釈できないため。既存ディレクトリならどちらもモードを触らない。
RUN mkdir -p /etc/chelly /etc/claude-code
COPY --chmod=0644 <<'EOF' /etc/chelly/AGENTS.md
- この環境はコンテナであり、コンテナのファイルシステム自体は終了時に破棄される
- ただし mount されたディレクトリはホスト側の実体または volume であり、コンテナ終了後も残る
- 起動時の作業ディレクトリはホストと同一のパスで mount されている
- git worktree から起動した場合は、メインリポジトリ側のディレクトリも同一のパスで mount されている
- 実際に mount されているディレクトリは /proc/self/mountinfo で確認できる
- 会話の再開は、前回のコンテナ、一時的に入れたツール、DB やプロセスの復元を意味しない
- 必要なツール、DB、プロセスの状態は使用前に確認し、会話履歴だけを根拠に存在すると扱わない
- 繰り返し必要な環境はリポジトリの devShell や既存のセットアップ手順で再現する
- コンテナが起動しても devShell に入れたとは限らない。期待した環境が無ければ起動時の診断や nix develop で原因を確かめる
EOF

RUN ln -s /etc/chelly/AGENTS.md /etc/claude-code/CLAUDE.md

# --------------------------------------------------------
# git worktree の破壊的操作を止める shim
# --------------------------------------------------------
# git worktree から起動すると .git 本体はマウントされるが他の worktree のディレクトリは
# コンテナ内に存在しない。この状態で prune / remove を実行すると、消えたように見える
# 他の worktree の登録ごと落としてしまうため、コンテナ内では実行させない。
# remove は対象がコンテナ内に実在するときだけ通す。コンテナ内で add した worktree を
# 片付けるのは正当な操作で、そこまで塞ぐと worktree を使う作業自体ができなくなる。
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
    prune)
        if [ "${worktree_seen}" = 1 ]; then
            echo "chelly: git worktree prune はコンテナ内では禁止されています" >&2
            echo "chelly: 他の worktree のディレクトリがコンテナ内に無いため、その登録まで消えます" >&2
            exit 1
        fi
        break
        ;;
    remove)
        if [ "${worktree_seen}" = 1 ]; then
            target=""
            for arg in "${args[@]:1}"; do
                case "${arg}" in
                --) continue ;;
                -*) continue ;;
                *)
                    target="${arg}"
                    break
                    ;;
                esac
            done
            # -C で移動した先を基準にした相対パスは shim の cwd では解決できないが、
            # その場合は実在しない扱いになって拒否されるだけなので安全側に倒しておく。
            if [ -z "${target}" ] || [ ! -d "${target}" ]; then
                echo "chelly: git worktree remove はコンテナ内に実在する worktree にしか使えません" >&2
                echo "chelly: ${target:-対象} はコンテナ内に無く、ホスト側にある worktree の登録を消す恐れがあります" >&2
                exit 1
            fi
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

# CLAUDE_CODE_EXECUTABLE で PATH の claude を指すのは、claude-agent-acp が既定で
# @anthropic-ai/claude-agent-sdk にぶら下がる native binary を使い、CLI の版が acp の
# リリース周期に縛られるため。バンドルを消さずに環境変数で上書きするのは、これが
# アダプタ側の公式な分岐 (claudeCliPath) であるため。
ENV \
    CLAUDE_CODE_EXECUTABLE=/home/warashi/.local/bin/claude \
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
# apple/container は VM 起動から数秒間、virtiofs のマウント点だけを root 所有に見せる
# (中のファイルはユーザー所有)。その間は git も nix の libgit2 も所有者チェックで
# リポジトリを開けず、entrypoint の devShell 判定が黙って素のシェルに落ちる。
# コンテナは単一ユーザーで、マウントされるのは自分のディレクトリだけなので、
# 所有者チェックが守るものはない。環境変数 GIT_CONFIG_* は libgit2 が読まないので
# gitconfig に書く。
RUN mkdir -p /home/warashi/.config/git && \
    git config --global core.untrackedcache false && \
    git config --global gc.worktreePruneExpire never && \
    git config --global safe.directory '*' && \
    git config --global user.name 'Shinnosuke Sawada-Dazai' && \
    git config --global user.email '3600530+Warashi@users.noreply.github.com'

# Claude CLI インストール
RUN mkdir -p /home/warashi/.claude /home/warashi/.copilot
ADD --chmod=0666 https://claude.ai/install.sh /tmp/claude-install.sh
RUN bash /tmp/claude-install.sh && rm -f /tmp/claude-install.sh

# Copilot CLI インストール
ADD --chmod=0666 https://gh.io/copilot-install /tmp/copilot-install.sh
RUN bash /tmp/copilot-install.sh && rm -f /tmp/copilot-install.sh

# Nix 設定（インストール自体は entrypoint が volume 側の /nix に対して行う）
RUN mkdir -p ~/.config/nix && \
    echo "experimental-features = nix-command flakes pipe-operators" >> ~/.config/nix/nix.conf

# shell.nix から unfree パッケージを使えるようにする
RUN mkdir -p ~/.config/nixpkgs && \
    echo "{ allowUnfree = true; }" > ~/.config/nixpkgs/config.nix

# 専用環境の ~/.claude と ~/.copilot は Podman volume なので、ホストの home-manager の
# activation では書けない。同じ生成物 (CLAUDE.md、settings の override、output-styles、
# skills、copilot-instructions.md) を起動時に volume へ写す。呼ぶのは CHELLY_AGENT_CONFIG が
# 指す bundle があるときだけで、通常入口は本人の実 ~/.claude を mount しているため触らない。
# settings は volume にある runtime の値を残して bundle を重ねる。Claude は host と同じ
# jq の * (配列は置き換え)、Copilot は host の deep_merge と同じ配列の和集合にする。
COPY --chown=warashi --chmod=0755 <<'EOF' /home/warashi/.local/bin/chelly-apply-agent-config
#!/bin/sh
set -eu

bundle="$1"
claude_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
copilot_dir="${HOME}/.copilot"

# bundle は Nix store の 0444/0555 なので mode を引き継ぐと次回の上書きで失敗する。
copy_tree() {
  rm -rf "$2"
  mkdir -p "$(dirname "$2")"
  cp -R --no-preserve=mode "$1" "$2"
}

merge_settings() {
  filter="$1" target="$2" override="$3"
  mkdir -p "$(dirname "${target}")"
  if [ ! -s "${target}" ]; then
    printf '{}\n' >"${target}"
  fi
  tmp="$(mktemp "${target}.XXXXXX")"
  jq -s "${filter}" "${target}" "${override}" >"${tmp}"
  mv "${tmp}" "${target}"
}

if [ -f "${bundle}/claude/CLAUDE.md" ]; then
  mkdir -p "${claude_dir}"
  cp --no-preserve=mode "${bundle}/claude/CLAUDE.md" "${claude_dir}/CLAUDE.md"
fi
if [ -d "${bundle}/claude/output-styles" ]; then
  copy_tree "${bundle}/claude/output-styles" "${claude_dir}/output-styles"
fi
for skill in "${bundle}"/claude/skills/*/; do
  [ -d "${skill}" ] || continue
  copy_tree "${skill}" "${claude_dir}/skills/$(basename "${skill}")"
done
if [ -f "${bundle}/claude/settings.json" ]; then
  merge_settings '.[0] * .[1]' "${claude_dir}/settings.json" "${bundle}/claude/settings.json"
fi

if [ -f "${bundle}/copilot/copilot-instructions.md" ]; then
  mkdir -p "${copilot_dir}"
  cp --no-preserve=mode "${bundle}/copilot/copilot-instructions.md" "${copilot_dir}/copilot-instructions.md"
fi
for skill in "${bundle}"/copilot/skills/*/; do
  [ -d "${skill}" ] || continue
  copy_tree "${skill}" "${copilot_dir}/skills/$(basename "${skill}")"
done
if [ -f "${bundle}/copilot/settings.json" ]; then
  merge_settings '
    def deep_merge($a; $b):
      if ($a | type == "object") and ($b | type == "object") then
        reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = deep_merge($a[$k]; $b[$k]))
      elif ($a | type == "array") and ($b | type == "array") then
        ($a + $b) | unique
      else
        $b
      end;
    deep_merge(.[0]; .[1])
  ' "${copilot_dir}/settings.json" "${bundle}/copilot/settings.json"
fi
EOF

COPY --chown=warashi --chmod=0755 <<'EOF' /home/warashi/.local/bin/chelly-entrypoint
#!/bin/sh

COPILOT_CUSTOM_INSTRUCTIONS_DIRS="/etc/chelly${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:+,${COPILOT_CUSTOM_INSTRUCTIONS_DIRS}}"
export COPILOT_CUSTOM_INSTRUCTIONS_DIRS

# ホストの store を共有しているときは、ホストと同じ版の nix が store path で渡される。
# イメージ側には nix が無く、~/.nix-profile も無いので、ここで PATH に足す。
if [ -n "${CHELLY_NIX_BIN:-}" ]; then
  PATH="${CHELLY_NIX_BIN}:${PATH}"
  export PATH
fi

# 専用環境の volume に、ホストと同じ Claude/Copilot の設定を写す。失敗は nix の
# インストールと同じく起動を止める。設定が無いまま agent が動くと本人の指示が効かない。
if [ -n "${CHELLY_AGENT_CONFIG:-}" ]; then
  "$(dirname "$0")/chelly-apply-agent-config" "${CHELLY_AGENT_CONFIG}" || exit 1
fi

# named volume の所有者をコンテナのユーザーに合わせる。podman はイメージ側のマウント先の
# 所有者を新規 volume に引き継ぐが、apple/container は ext4 を作ったままの root 所有で
# マウントする (apple/container#729, #745)。root 所有のままだと nix インストーラも
# cache も書けない。再帰しないのは、volume の中身は既に自分の所有で作られているため。
# ホストの store を read-only で共有しているときは /nix は root 所有のままでよく、
# chown も通らないので対象から外す。
chelly_volume_dirs="${HOME}/.cache/go-build ${HOME}/.cache/nix ${HOME}/go/pkg/mod"
if [ -z "${CHELLY_NIX_BIN:-}" ]; then
  chelly_volume_dirs="/nix ${chelly_volume_dirs}"
fi
for chelly_dir in ${chelly_volume_dirs}; do
  if [ -d "${chelly_dir}" ] && [ "$(stat -c %u "${chelly_dir}")" != "$(id -u)" ]; then
    sudo chown "$(id -u):$(id -g)" "${chelly_dir}"
  fi
done

# 入れ子の rootless podman が使う tun (pasta) と fuse (fuse-overlayfs) を一般ユーザーに開ける。
# podman の --device はホスト側の 0666 をそのまま渡すが、apple/container はノードを
# 0600 root で置くだけなので、ここで直す。
for chelly_dev in /dev/net/tun /dev/fuse; do
  if [ -c "${chelly_dev}" ] && [ ! -w "${chelly_dev}" ]; then
    sudo chmod 0666 "${chelly_dev}"
  fi
done

# volume モードでは nix の profile 実体は home 側にあってコンテナごとに消えるため、
# インストーラは実質毎回走る。store は /nix の named volume に残っているので、追加されるのは差分だけ。
# flock で直列化しているのは、volume を共有する複数コンテナが同時に起動したときに
# 同じ store へ並行に書き込ませないため。判定をロックの外に出すと、待たされた側が
# 古い判定結果のまま走ってしまうので、判定ごとロック内に入れている。
# 出力を溜めて失敗時だけ stderr へ流すのは、成功時に進捗表示で画面を汚さず、かつ
# stdout でプロトコルを話す ACP エージェントへ何も漏らさないため。
# ロックの外にも判定があるのは、/nix が read-only でロックファイル自体を作れない
# 場合 (ホストの store を共有しているとき) に flock で落ちないようにするため。
if ! command -v nix >/dev/null 2>&1; then
  if ! chelly_nix_install_log="$(flock /nix/.chelly-install.lock sh -c '
      nix --version >/dev/null 2>&1 ||
        /opt/nix-installer/install --no-daemon --no-channel-add --no-modify-profile
    ' 2>&1)"; then
    printf '%s\n' "${chelly_nix_install_log}" >&2
    exit 1
  fi
fi

# .#. は既定の package ではなく outputs 全体を選ぶ。getFlake の impure 評価や
# store path への置き換えを避け、nix develop と同じ純粋評価・Git メタデータを使う。
# 評価に失敗しても、壊れた flake をコンテナ内で直せるように起動は続ける。
chelly_flake_has_shell=false
if [ -f flake.nix ]; then
  if ! chelly_system="$(nix config show system)"; then
    echo "chelly: unable to inspect development environment; starting without it" >&2
  elif ! chelly_system_expr="$(
    printf '%s' "${chelly_system}" | jq -Rrs '@json | gsub("\\$\\{"; "\\${")'
  )"; then
    echo "chelly: unable to inspect development environment; starting without it" >&2
  else
    if ! chelly_flake_shell_type="$(
      nix eval --accept-flake-config --raw '.#.' --apply "
      flake:
      let
        system = ${chelly_system_expr};
        candidates =
          if flake ? devShells && builtins.hasAttr system flake.devShells &&
            flake.devShells.\${system} ? default then
            [ flake.devShells.\${system}.default ]
          else if flake ? devShell && flake.devShell ? \${system} then
            [ flake.devShell.\${system} ]
          else if flake ? packages && builtins.hasAttr system flake.packages &&
            flake.packages.\${system} ? default then
            [ flake.packages.\${system}.default ]
          else if flake ? defaultPackage && flake.defaultPackage ? \${system} then
            [ flake.defaultPackage.\${system} ]
          else
            [];
        shell = builtins.head candidates;
      in
        if candidates == [] then \"none\"
        else if builtins.isAttrs shell && (shell.type or null) == \"derivation\" then \"derivation\"
        else throw \"default development environment is not a derivation\"
      "
    )"; then
      echo "chelly: unable to evaluate default development environment; starting without it" >&2
    elif [ "${chelly_flake_shell_type}" != none ]; then
      chelly_flake_has_shell=true
    fi
  fi
fi

if [ "${chelly_flake_has_shell}" = true ]; then
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
  if [ "$#" -eq 0 ]; then
    exec bash
  fi
  exec "$@"
fi
EOF

ENTRYPOINT ["/home/warashi/.local/bin/chelly-entrypoint"]
