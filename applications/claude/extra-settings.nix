{
  lib,
  writeShellApplication,
  jq,
  sources,
}:
with lib;
let
  readSource = source: ''
    if [ -f ${escapeShellArg source.path} ]; then
      jq ${escapeShellArg source.filter} ${escapeShellArg source.path}
    ${
      if source.optional then
        ''
          else
            echo '{}'
          fi
        ''
      else
        ''
          else
            echo "claude: settings source ${source.path} not found" >&2
            exit 1
          fi
        ''
    }'';
in
writeShellApplication {
  name = "claude-extra-settings";
  runtimeInputs = [ jq ];
  # source が欠けたときに途中までのマージ結果を出力しないよう、一度集めてからマージする。
  text = ''
    outputs="$(mktemp)"
    trap 'rm -f "$outputs"' EXIT
    {
      echo '{}'
      ${concatMapStringsSep "\n" readSource sources}
    } >"$outputs"
    jq -s 'reduce .[] as $source ({}; . * $source)' "$outputs"
  '';
}
