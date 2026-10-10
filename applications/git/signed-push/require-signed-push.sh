#!/usr/bin/env bash
# pre-push hook: remote にまだ無い commit に署名の無いものがあれば push を止める。
# 署名の正しさは見ず、gpgsig ヘッダの有無だけで判定する。
set -euo pipefail

remote=$1
zero=$(git hash-object --stdin </dev/null | tr 0-9a-f 0)

unsigned=()
while read -r _local_ref local_sha _remote_ref remote_sha; do
  [ "$local_sha" = "$zero" ] && continue
  exclude=(--not "--remotes=$remote")
  if [ "$remote_sha" != "$zero" ] && git cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
    exclude+=("$remote_sha")
  fi
  while read -r commit; do
    if ! git cat-file commit "$commit" | sed '/^$/q' | grep -q '^gpgsig'; then
      unsigned+=("$commit")
    fi
  done < <(git rev-list "$local_sha" "${exclude[@]}")
done

if [ "${#unsigned[@]}" -gt 0 ]; then
  echo "署名の無い commit があるので push を止めた (意図したものなら --no-verify):" >&2
  git log --no-walk=unsorted --format='  %h %s' "${unsigned[@]}" >&2
  exit 1
fi
