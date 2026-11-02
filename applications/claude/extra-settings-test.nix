{
  callPackage,
  runCommand,
  jq,
}:
let
  build = sources: callPackage ./extra-settings.nix { inherit sources; };
  script = build [
    {
      path = "first.json";
      filter = ".";
      optional = false;
    }
    {
      path = "second.json";
      filter = "{env: {B: .env.B}}";
      optional = false;
    }
    {
      path = "missing.json";
      filter = ".";
      optional = true;
    }
  ];
  required = build [
    {
      path = "missing.json";
      filter = ".";
      optional = false;
    }
  ];
  empty = build [ ];
in
runCommand "claude-extra-settings-test" { nativeBuildInputs = [ jq ]; } ''
  printf '%s' '{"env":{"A":"1","B":"first"},"keep":true}' > first.json
  printf '%s' '{"env":{"B":"second","C":"dropped"}}' > second.json

  # 後の source が先の source を上書きし、filter で選んだキーだけが入る。存在しない optional は無視する。
  ${script}/bin/claude-extra-settings | jq -e '. == {"env":{"A":"1","B":"second"},"keep":true}'

  # optional でない source が無ければ失敗する。
  if ${required}/bin/claude-extra-settings; then
    echo "required source missing but succeeded" >&2
    exit 1
  fi

  ${empty}/bin/claude-extra-settings | jq -e '. == {}'
  mkdir "$out"
''
