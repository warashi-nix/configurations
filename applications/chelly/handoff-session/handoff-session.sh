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
  done < <(list_clones)
  ((${#mounts[@]})) || fail "no workspace named '$name' under $root"
fi

if ((${#mounts[@]})); then
  extra=$(
    IFS=,
    echo "${mounts[*]}"
  )
  export CHELLY_ADDITIONAL_MOUNTS="$base_mounts,$extra"
fi
exec "$chelly" "$@"
