#!/usr/bin/env bash
# 本文を Slack の Incoming Webhook に POST する。本文は引数があれば引数、無ければ stdin。
# 本文は信頼できない入力を含みうるので、Slack の制御文字をエスケープしてリンクや
# メンションの記法にさせない。
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: slack-notify URL_FILE [TEXT...]" >&2
  exit 2
fi
url_file=$1
shift

if [[ $# -gt 0 ]]; then
  text="$*"
else
  text=$(cat)
fi
[[ -n $text ]] || text="(本文なし)"

url=$(<"$url_file")
# URL は curl の設定として渡すので、引用符や改行で別の設定を足せないようにする。
if [[ -z $url || $url == *[\"\\$'\n\r']* ]]; then
  echo "slack-notify: $url_file does not hold a single URL" >&2
  exit 1
fi

host=$(uname -n)
host=${host%%.*}

jq -n --arg text "[$host] $text" \
  '{text: ($text | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;"))}' |
  # URL は秘密なので argv に載せず、process substitution の設定ファイルから渡す。
  # 応答の本文は URL を含みうるので捨て、失敗は exit status だけで返す。
  curl --silent --show-error --fail --max-time 20 \
    --config <(printf 'url = "%s"\n' "$url") \
    --header 'Content-Type: application/json' \
    --data-binary @- \
    --output /dev/null
