#!/usr/bin/env bash
# chelly run の前に、同じ handoff 名の専用 clone を集めて本人と同じ ghq の path に mount する。
# 設定は Nix の wrapper が HANDOFF_SESSION_* で渡す。chelly には渡さない。
#   HANDOFF_SESSION_WORKSPACES  専用領域
#   HANDOFF_SESSION_MOUNTS      chelly の設定にある additional_mounts (カンマ区切り)
#   HANDOFF_SESSION_FIXED       設定で常に mount する clone (改行区切り)
#   HANDOFF_SESSION_CHELLY      本体の chelly
set -euo pipefail

usage() {
  echo "usage: chelly [--handoff NAME] run [-- command [args...]]" >&2
  exit 2
}

fail() {
  echo "chelly: $*" >&2
  exit 1
}

workspaces=$HANDOFF_SESSION_WORKSPACES
base_mounts=$HANDOFF_SESSION_MOUNTS
fixed_list=$HANDOFF_SESSION_FIXED
chelly=$HANDOFF_SESSION_CHELLY
unset HANDOFF_SESSION_WORKSPACES HANDOFF_SESSION_MOUNTS HANDOFF_SESSION_FIXED HANDOFF_SESSION_CHELLY

# default branch の名前は参加 repo を表さないので集めない。
excluded_names=(main master)

name=
if [[ ${1:-} == --handoff ]]; then
  [[ $# -ge 3 && -n $2 && $3 == run ]] || usage
  name=$2
  shift 2
fi
[[ ${1:-} == run ]] || exec "$chelly" "$@"

root=$(cd -P -- "$workspaces" && pwd -P)
fixed=()
while IFS= read -r path; do
  [[ -n $path ]] || continue
  fixed+=("$(cd -P -- "$path" 2>/dev/null && pwd -P || echo "$path")")
done <<<"$fixed_list"

is_fixed() {
  local path
  for path in "${fixed[@]}"; do
    [[ $1 == "$path" ]] && return 0
  done
  return 1
}

# clone は .git を持つ最初のディレクトリで、その中には下りない。find は symlink を辿らず、
# -type d は symlink に一致しないので、専用領域の外にある clone は集まらない。
list_clones() {
  find "$root" -mindepth 2 \( -name .git -prune \) -o \
    \( -type d -exec test -e '{}/.git' ';' -prune -print0 \)
}

mounts=()
# 書き込む clone。集めた clone と cwd の clone で、設定で常に mount する clone は除く。
targets=()

add_target() {
  local target
  is_fixed "$1" && return
  for target in "${targets[@]}"; do
    [[ $1 == "$target" ]] && return
  done
  targets+=("$1")
}

# cwd を含む clone は、領域の root から下りて最初に .git を持つディレクトリ。
cwd_clone() {
  local dir path component
  local -a components
  dir=$(pwd -P)
  [[ $dir == "$root"/?* ]] || return 0
  path=$root
  IFS=/ read -r -a components <<<"${dir#"$root"/}"
  for component in "${components[@]}"; do
    path=$path/$component
    if [[ -e $path/.git ]]; then
      add_target "$path"
      return
    fi
  done
}

# 同じ clone に複数の agent が書かないよう、他のコンテナが mount している clone では起動しない。
# 単独起動は cwd を mount するので、clone の下のディレクトリもその clone の使用にあたる。
refuse_busy_targets() {
  local ids source target
  local -a busy=()
  ((${#targets[@]})) || return 0
  ids=$(podman ps --quiet) || fail "cannot list running containers to check workspaces in use"
  [[ -n $ids ]] || return 0
  while IFS= read -r source; do
    [[ $source == /* ]] || continue
    source=$(realpath -m -- "$source")
    for target in "${targets[@]}"; do
      if [[ $source == "$target" || $source == "$target"/* ]]; then
        busy+=("$target")
      fi
    done
  done < <(
    # shellcheck disable=SC2086  # ID は空白区切りの一覧として渡す
    podman inspect --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' $ids
  )
  ((${#busy[@]} == 0)) ||
    fail "workspace in use by another container: $(printf '%s\n' "${busy[@]}" | sort -u | tr '\n' ' ')"
}

if [[ -n $name ]]; then
  for excluded in "${excluded_names[@]}"; do
    if [[ $name == "$excluded" ]]; then
      echo "chelly: '$name' is a default branch name; starting a single session" >&2
      name=
      break
    fi
  done
fi
if [[ -n $name ]]; then
  id=$(chelly-handoff id "$name") || fail "invalid handoff name '$name'"
  while IFS= read -r -d '' clone; do
    [[ ${clone##*/} == "$id" ]] || continue
    is_fixed "$clone" && continue
    project=${clone#"$root"/}
    project=${project%/*}
    mounts+=("$clone:/home/warashi/ghq/$project")
    add_target "$clone"
  done < <(list_clones)
  ((${#mounts[@]})) || fail "no workspace named '$name' under $root"
fi
cwd_clone
refuse_busy_targets

if ((${#mounts[@]})); then
  extra=$(
    IFS=,
    echo "${mounts[*]}"
  )
  export CHELLY_ADDITIONAL_MOUNTS="$base_mounts,$extra"
fi
exec "$chelly" "$@"
