#!/usr/bin/env bash
set -euo pipefail

# TARGET_SYSTEM は workflow の matrix から渡される。
# checks を列挙して個別に渡すのは、nix build が attrset の installable を
# 受け付けないため。host の toplevel と devShell も checks に含まれるので、
# 対象はこれで尽きる。単一の nix build に混ぜれば --keep-going が
# ビルド失敗とテスト失敗を一度に出す。
# macOS 標準の bash 3.2 には mapfile が無いので read で配列に積む。
checks=$(nix eval ".#checks.${TARGET_SYSTEM}" --apply builtins.attrNames --json | jq -r '.[]')

targets=()
while IFS= read -r check; do
  targets+=(".#checks.${TARGET_SYSTEM}.${check}")
done <<<"${checks}"

nix build --accept-flake-config --keep-going --no-link --show-trace --eval-system "${TARGET_SYSTEM}" --print-out-paths "${targets[@]}"
