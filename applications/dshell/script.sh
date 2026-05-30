BUILD_NO_CACHE=0
if [ "${1:-}" = "--build-no-cache" ]; then
  BUILD_NO_CACHE=1
  shift
fi

# 1. パスの解決と XDG 設定ディレクトリの特定
TARGET_DIR=$(realpath "$(pwd)")
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

FALLBACK_CONFIG_DIR="$CONFIG_HOME/dshell/default"
FALLBACK_CONFIG="$FALLBACK_CONFIG_DIR/devcontainer.json"

OVERRIDE_CONFIG_DIR="$CONFIG_HOME/dshell/override"
OVERRIDE_CONFIG="$OVERRIDE_CONFIG_DIR/devcontainer.json"

TMP_CONFIG_DIR="$(mktemp -d)"
TMP_CONFIG="$TMP_CONFIG_DIR/.devcontainer/devcontainer.json"
mkdir -p "$(dirname "$TMP_CONFIG")"

cleanup() {
  # クリーンアップ関数
  CONTAINER_ID=$(docker ps -q --filter "label=devcontainer.local_folder=$TARGET_DIR")
  [ -n "$CONTAINER_ID" ] && docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID"
  rm -rf "$TMP_CONFIG_DIR"
}
trap cleanup EXIT

merge() {
  local f files=()
  for f in "$@"; do [[ -f $f ]] && files+=("$f"); done

  jq -n 'reduce inputs as $item ({}; . * $item)' "${files[@]}"
}

MERGE_TARGETS=()
# 2. devcontainer.json の探索
if [ -f "$TARGET_DIR/.devcontainer/devcontainer.json" ]; then
  MERGE_TARGETS+=("$TARGET_DIR/.devcontainer/devcontainer.json")
elif [ -f "$TARGET_DIR/.devcontainer.json" ]; then
  MERGE_TARGETS+=("$TARGET_DIR/.devcontainer.json")
elif [ -f "$FALLBACK_CONFIG" ]; then
  MERGE_TARGETS+=("$FALLBACK_CONFIG")
else
  echo >&2 "❌ エラー: devcontainer.json も $FALLBACK_CONFIG も見つかりません。"
  exit 1
fi

if [ -f "$OVERRIDE_CONFIG" ]; then
  MERGE_TARGETS+=("$OVERRIDE_CONFIG")
fi

# devcontainer.json のマージと一時ファイルへの出力
merge "${MERGE_TARGETS[@]}" >"$TMP_CONFIG"

# devcontainer-lock.json のロックファイルのマージと一時ファイルへの出力
LOCK_MERGE_TARGETS=()
for file in "${MERGE_TARGETS[@]}"; do
  LOCK_FILE="$(dirname "$file")/devcontainer-lock.json"
  if [ -f "$LOCK_FILE" ]; then
    LOCK_MERGE_TARGETS+=("$(dirname "$file")/devcontainer-lock.json")
  fi
done
echo >&2 "lock merge targets: ${LOCK_MERGE_TARGETS[*]}"
merge "${LOCK_MERGE_TARGETS[@]}" >"$(dirname "$TMP_CONFIG")/devcontainer-lock.json"

# 2. Git 情報などの取得
U_NAME=$(git config --get user.name)
U_EMAIL=$(git config --get user.email)
GIT_ROOT=$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null)
GIT_COMMON_DIR="$(cd "$(git -C "$TARGET_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && cd .. && pwd)"

COMMON_OPTS=()
COMMON_OPTS+=("--mount-workspace-git-root")
COMMON_OPTS+=("--config" "$TMP_CONFIG")
COMMON_OPTS+=("--workspace-folder" "$TARGET_DIR")

UP_ARGS=("")
[ -n "$GIT_COMMON_DIR" ] && [[ $GIT_COMMON_DIR != "$GIT_ROOT" ]] && UP_ARGS+=("--mount" "type=bind,source=$GIT_COMMON_DIR,target=$GIT_COMMON_DIR")
[ "$BUILD_NO_CACHE" -eq 1 ] && UP_ARGS+=("--build-no-cache")

# 3. 起動
devcontainer up "${COMMON_OPTS[@]}" "${UP_ARGS[@]}"

# 4. Git 設定の注入 & シェル起動
devcontainer exec "${COMMON_OPTS[@]}" git config --global --add safe.directory '*'
[ -n "$U_NAME" ] && devcontainer exec "${COMMON_OPTS[@]}" git config --global user.name "$U_NAME"
[ -n "$U_EMAIL" ] && devcontainer exec "${COMMON_OPTS[@]}" git config --global user.email "$U_EMAIL"

# 5. 引数で指定されていない場合、デフォルトコマンドを設定
COMMANDS=("$@")
if [ ${#COMMANDS[@]} -eq 0 ]; then
  COMMANDS=("/bin/zsh" "--login")
fi

# 6. コマンドの実行
devcontainer exec "${COMMON_OPTS[@]}" "${COMMANDS[@]}"
