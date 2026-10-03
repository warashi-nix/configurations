{ writeShellApplication, jq }:
writeShellApplication {
  name = "run-or-raise";
  runtimeInputs = [ jq ];
  # フローティングを除くのは、quick-input のような一時的なウィンドウではなく
  # 作業中のウィンドウへ戻るため。
  text = ''
    app_id=$1
    shift
    id=$(niri msg -j windows | jq --arg app_id "$app_id" \
      'first(.[] | select(.app_id == $app_id and (.is_floating | not)) | .id) // empty')
    if [ -n "$id" ]; then
      niri msg action focus-window --id "$id"
    else
      exec "$@"
    fi
  '';
}
