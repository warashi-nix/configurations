#!/usr/bin/env bash
set -euo pipefail

LOCK="applications/emacs/twist/lock/flake.lock"

# 上流に変更が無い日でも 58 個のジョブが Nix インストールから実フェッチまで
# 一通り走ってしまうため、ここで ls-remote による事前判定を挟んで matrix を絞る。
# ジョブ側で判定しないのは、判定した時点で既にジョブの固定費を払っているため。
list_all() {
  jq -r '
    . as $lock
    | $lock.nodes[$lock.root].inputs
    | to_entries[]
    | $lock.nodes[.value] as $node
    | [
        .key,
        $node.locked.rev,
        (if $node.locked.type == "github"
         then "https://github.com/\($node.locked.owner)/\($node.locked.repo)"
         else $node.locked.url
         end),
        ($node.original.ref // $node.locked.ref // "HEAD")
      ]
    | @tsv
  ' "$LOCK"
}

check_one() {
  local name rev url ref remote
  IFS=$'\t' read -r name rev url ref <<<"$1"

  case "$ref" in
  HEAD | refs/*) ;;
  # 短縮 ref はブランチとして解決する。同名タグが居ると ls-remote が
  # 複数行返して、どちらを採ったか分からなくなる
  *) ref="refs/heads/${ref}" ;;
  esac

  remote=$(git ls-remote "$url" "$ref" 2>/dev/null | cut -f1 | head -n1)

  # 問い合わせに失敗したときは更新対象に残す。取りこぼしたまま静かに
  # 更新が止まるより、無駄に 1 ジョブ走る方がまし
  if [ -z "$remote" ] || [ "$remote" != "$rev" ]; then
    echo "$name"
  fi
}
export -f check_one

if [ "${SKIP_FILTER:-false}" = "true" ]; then
  list_all | cut -f1 | sort | jq -cnR '[inputs | select(length > 0)]'
else
  list_all | xargs -d '\n' -P 16 -I{} bash -c 'check_one "$@"' _ {} | sort | jq -cnR '[inputs | select(length > 0)]'
fi
