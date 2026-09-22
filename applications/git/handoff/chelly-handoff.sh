#!/usr/bin/env bash
# shellcheck disable=SC2016  # 専用ユーザー側の script は意図的に単一引用符で渡す
# 専用ユーザーの clone と本人の repository の間で Git bundle だけを受け渡す。
# 差分の確認と取り込みは Magit などの通常の Git 操作に任せ、状態は remote 設定だけに置く。
set -euo pipefail

workspaces="${CHELLY_HANDOFF_WORKSPACES:-/srv/chelly-workspaces}"

usage() {
  cat >&2 <<'EOF'
usage: chelly-handoff create [NAME]
       chelly-handoff fetch [NAME]
       chelly-handoff update [NAME]
       chelly-handoff remove [NAME] [--force]

create  現在の HEAD から専用領域の <repo 名>/NAME に clone を作り、remote handoff-NAME を追加する
fetch   専用 clone の HEAD までの commit を remote handoff-NAME に取り込み、新規追跡ファイルを検査する
update  専用 clone を本人の branch の先端に合わせ直す (未取得の commit や未コミット変更があれば止まる)
        agent が切った branch は消し、create 時の branch に戻す
remove  remote と bundle を消し、専用 clone を削除する (未取得の commit があれば --force が要る)

NAME を省略すると現在の branch 名を使う。
EOF
  exit 2
}

fail() {
  echo "chelly-handoff: $*" >&2
  exit 1
}

# 専用ユーザー側で動かすスクリプトは引数だけを受け取り、本人の環境変数を継承しない。
# stdin は bundle を渡す create 以外では /dev/null にする。端末のまま渡すと
# podman が --tty 無しで端末を attach したまま終了せず、CPU を使い続ける。
agent() {
  local script=$1
  shift
  (
    cd "$workspaces" &&
      env -u SSH_AUTH_SOCK -u SSH_AGENT_PID \
        -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
        chelly-agent run -- bash -euc "$script" bash "$@"
  )
}

create_script='
umask 0027
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1
parent=$1 dest=$2 base=$3 branch=$4
case "$dest" in "$parent"/?*/?*) ;; *) exit 90 ;; esac
case "$dest" in *..*) exit 90 ;; esac
if [ -e "$dest" ] || [ -L "$dest" ]; then
  echo "workspace already exists: $dest" >&2
  exit 1
fi
mkdir -p -- "${dest%/*}"
bundle="${dest}.bundle.$$"
trap "rm -f -- \"$bundle\"" EXIT
cat >"$bundle"
mkdir -- "$dest"
git -c init.defaultBranch="$branch" clone --quiet --no-checkout --template= "$bundle" "$dest"
cd "$dest"
git remote remove origin
git -c core.hooksPath=/dev/null switch --quiet -c "$branch" "$base"
git config --local commit.gpgsign false
test "$(git rev-parse HEAD)" = "$base"
test -z "$(git -c core.fsmonitor=false status --porcelain=v1 --untracked-files=all)" ||
  { echo "new agent workspace is not clean" >&2; exit 1; }
'

# agent が branch を切っても切らなくても回収できるよう、HEAD の指す先を bundle にする。
# bundle の head 名 (refs/heads/… か、detached なら HEAD) は本人側が読んで ref 名を決める。
fetch_script='
umask 0077
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1
parent=$1 workspace=$2 base=$3
case "$workspace" in "$parent"/?*/?*) ;; *) exit 90 ;; esac
case "$workspace" in *..*) exit 90 ;; esac
cd "$workspace"
test "$(git rev-parse --verify HEAD^{commit})" != "$base" ||
  { echo "agent created no commits" >&2; exit 1; }
test -z "$(git -c core.fsmonitor=false status --porcelain=v1 --untracked-files=all)" ||
  { echo "agent workspace is not clean; commit or discard first" >&2; exit 1; }
ref=$(git symbolic-ref --quiet HEAD) || ref=HEAD
bundle="${workspace}.bundle.$$"
trap "rm -f -- \"$bundle\"" EXIT
git -c core.hooksPath=/dev/null bundle create --quiet "$bundle" "^$base" "$ref"
cat "$bundle"
'

probe_script='
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1
parent=$1 workspace=$2
case "$workspace" in "$parent"/?*/?*) ;; *) exit 90 ;; esac
case "$workspace" in *..*) exit 90 ;; esac
test -d "$workspace" || { echo missing; exit 0; }
cd "$workspace"
git rev-parse --verify HEAD^{commit}
git symbolic-ref --quiet --short HEAD || echo
git -c core.fsmonitor=false status --porcelain=v1 --untracked-files=all | wc -l
'

# 取り込みで SHA が変わるので rebase はせず、clone をそのまま本人の先端に置き換える。
# 捨ててよいことは本人側で probe の結果を見て判断済みで、ここでは clean であることだけ再確認する。
# create 直後と同じ形に戻すため、agent が切っていた branch は消して記録 branch に載せ直す。
# 先端が base から動いていないと bundle は作れないので、stdin が空なら先端の存在だけ確かめる。
update_script='
umask 0027
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1
parent=$1 workspace=$2 branch=$3 tip=$4
case "$workspace" in "$parent"/?*/?*) ;; *) exit 90 ;; esac
case "$workspace" in *..*) exit 90 ;; esac
cd "$workspace"
test -z "$(git -c core.fsmonitor=false status --porcelain=v1 --untracked-files=all)" ||
  { echo "agent workspace is not clean; commit or discard first" >&2; exit 1; }
bundle="${workspace}.bundle.$$"
trap "rm -f -- \"$bundle\"" EXIT
cat >"$bundle"
if [ -s "$bundle" ]; then
  git bundle verify --quiet "$bundle"
  git -c core.hooksPath=/dev/null fetch --quiet --no-tags "$bundle" "refs/heads/$branch"
  test "$(git rev-parse --verify FETCH_HEAD^{commit})" = "$tip"
else
  git cat-file -e "$tip^{commit}"
fi
previous=$(git symbolic-ref --quiet --short HEAD) || previous=
git -c core.hooksPath=/dev/null switch --quiet --force -C "$branch" "$tip"
if [ -n "$previous" ] && [ "$previous" != "$branch" ]; then
  git branch --quiet -D "$previous"
fi
'

remove_script='
parent=$1 workspace=$2
case "$workspace" in "$parent"/?*/?*) ;; *) exit 90 ;; esac
case "$workspace" in *..*) exit 90 ;; esac
rm -rf -- "$workspace"
rmdir -- "${workspace%/*}" 2>/dev/null || true
'

name_pattern='^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'

# NAME を省略したら現在の branch 名を使う。専用領域の path になるので '/' は許さない。
resolve_name() {
  if [[ -n $1 ]]; then
    [[ $1 =~ $name_pattern ]] ||
      fail "NAME must start with an ASCII letter or digit and contain only letters, digits, '.', '_' or '-'"
    name=$1
    return
  fi
  name=$(git symbolic-ref --quiet --short HEAD) || fail "check out a named branch first or pass NAME"
  [[ $name =~ $name_pattern ]] || fail "branch '$name' is not usable as a workspace name; pass NAME"
}

repo_paths() {
  toplevel=$(git rev-parse --show-toplevel) || fail "run inside the owner's repository"
  gitdir=$(git rev-parse --path-format=absolute --git-common-dir)
  remote="handoff-$name"
  bundle="$gitdir/chelly-handoff/$name.bundle"
}

create() {
  resolve_name "$1"
  repo_paths
  ! git config --get "remote.$remote.url" >/dev/null || fail "remote $remote already exists"
  branch=$(git symbolic-ref --quiet --short HEAD) || fail "check out a named branch first"
  base=$(git rev-parse --verify 'HEAD^{commit}')
  project=${toplevel##*/}
  [[ $project =~ $name_pattern ]] || fail "repository directory name '$project' is not usable under $workspaces"
  workspace="$workspaces/$project/$name"
  git bundle create --quiet - HEAD |
    agent "$create_script" "$workspaces" "$workspace" "$base" "$branch"
  mkdir -p "$gitdir/chelly-handoff"
  git remote add "$remote" "$bundle"
  git config "remote.$remote.chelly-base" "$base"
  git config "remote.$remote.chelly-branch" "$branch"
  git config "remote.$remote.chelly-workspace" "$workspace"
  echo "$workspace"
}

# worktree から create した場合も同じ領域を指せるよう、path は remote 設定から読む。
recorded_paths() {
  base=$(git config --get "remote.$remote.chelly-base") || fail "remote $remote was not created by chelly-handoff"
  branch=$(git config --get "remote.$remote.chelly-branch")
  workspace=$(git config --get "remote.$remote.chelly-workspace")
}

fetch() {
  resolve_name "$1"
  repo_paths
  recorded_paths
  mkdir -p "$gitdir/chelly-handoff"
  agent "$fetch_script" "$workspaces" "$workspace" "$base" </dev/null >"$bundle.tmp"
  git bundle verify --quiet "$bundle.tmp"
  mv -f -- "$bundle.tmp" "$bundle"
  # bundle の head は agent の HEAD ひとつ。detached HEAD は記録 branch の名前で受ける。
  head_ref=$(git bundle list-heads "$bundle" | {
    read -r _ ref
    echo "$ref"
  })
  case "$head_ref" in
  refs/heads/?*) head_name=${head_ref#refs/heads/} ;;
  HEAD) head_name=$branch ;;
  *) fail "unexpected bundle head '$head_ref'" ;;
  esac
  tip="refs/remotes/$remote/$head_name"
  # agent が前回と別の branch に居たら古い名前の ref は紛らわしいだけで、
  # feat/topic の後に feat が来ると directory と衝突して fetch できないので、先に全部消す。
  git for-each-ref --format='delete %(refname)' "refs/remotes/$remote/" | git update-ref --stdin
  git fetch --quiet --no-tags "$remote" "+$head_ref:$tip"
  echo "fetched $(git rev-parse --short "$tip") as $remote/$head_name; review with $base..$remote/$head_name"
  git-check-new-ignored --object-repo "$gitdir" --policy-repo "$toplevel" "$base" "$tip"
}

# probe の出力は HEAD の commit、HEAD の branch 名 (detached なら空)、未コミット変更の行数。
probe_agent() {
  probe=$(agent "$probe_script" "$workspaces" "$workspace" </dev/null) ||
    fail "cannot probe agent workspace $workspace"
  [[ $probe != missing ]] || return 1
  mapfile -t lines <<<"$probe"
  head=${lines[0]}
  head_branch=${lines[1]}
  dirty=${lines[2]}
}

# 専用 clone の HEAD が本人の repo にあり、未コミット変更も無いときだけ、clone を捨ててよい。
require_agent_work_collected() {
  probe_agent || fail "agent workspace $workspace is missing; run create"
  git cat-file -e "$head^{commit}" 2>/dev/null ||
    fail "agent commit $head is not in this repository; run fetch first"
  [[ $dirty == 0 ]] || fail "agent workspace has uncommitted changes; commit and fetch, or discard them first"
}

# ff-only で取り込むと先端の SHA は clone と一致したまま agent の branch に居るので、
# branch も記録どおりのときだけ up to date とみなす。先端が base から動いていなければ
# bundle は作れないので、その場合は空の stdin を渡す。
update() {
  resolve_name "$1"
  repo_paths
  recorded_paths
  tip=$(git rev-parse --verify "refs/heads/$branch^{commit}") || fail "branch $branch does not exist here"
  require_agent_work_collected
  if [[ $head == "$tip" && $head_branch == "$branch" ]]; then
    echo "$remote is up to date at $(git rev-parse --short "$tip")"
    return
  fi
  if [[ $base == "$tip" ]]; then
    agent "$update_script" "$workspaces" "$workspace" "$branch" "$tip" </dev/null
  else
    git bundle create --quiet - "^$base" "refs/heads/$branch" |
      agent "$update_script" "$workspaces" "$workspace" "$branch" "$tip"
  fi
  git config "remote.$remote.chelly-base" "$tip"
  git for-each-ref --format='delete %(refname)' "refs/remotes/$remote/" | git update-ref --stdin
  rm -f -- "$bundle" "$bundle.tmp"
  echo "updated $remote to $(git rev-parse --short "$tip"); previous base was $(git rev-parse --short "$base")"
}

remove() {
  resolve_name "$1"
  repo_paths
  force=false
  [[ ${2:-} == --force ]] && force=true
  if git config --get "remote.$remote.chelly-workspace" >/dev/null; then
    recorded_paths
    probe_agent || probe=missing
  else
    probe=missing
  fi
  if [[ $probe != missing ]] && ! $force; then
    git cat-file -e "$head^{commit}" 2>/dev/null ||
      fail "agent commit $head is not in this repository; run fetch first or pass --force"
    [[ $dirty == 0 ]] || fail "agent workspace has uncommitted changes; pass --force to discard them"
  fi
  [[ $probe == missing ]] || agent "$remove_script" "$workspaces" "$workspace" </dev/null
  if git config --get "remote.$remote.url" >/dev/null; then
    git remote remove "$remote"
  fi
  rm -f -- "$bundle" "$bundle.tmp"
  echo "removed $remote"
}

[[ $# -ge 1 ]] || usage
case "$1" in
create)
  [[ $# -le 2 ]] || usage
  create "${2:-}"
  ;;
fetch)
  [[ $# -le 2 ]] || usage
  fetch "${2:-}"
  ;;
update)
  [[ $# -le 2 ]] || usage
  update "${2:-}"
  ;;
remove)
  if [[ ${2:-} == --force ]]; then
    [[ $# -eq 2 ]] || usage
    remove "" --force
  else
    [[ $# -le 3 ]] || usage
    remove "${2:-}" "${3:-}"
  fi
  ;;
*) usage ;;
esac
