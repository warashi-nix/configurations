{
  callPackage,
  runCommand,
  writeShellScriptBin,
}:
let
  runOrRaise = callPackage ./run-or-raise.nix { };
  fakeNiri = writeShellScriptBin "niri" ''
    case "$*" in
      "msg -j windows") cat "$WINDOWS" ;;
      "msg action focus-window --id "*) echo "focus $5" >> "$LOG" ;;
      *) echo "unexpected: $*" >&2; exit 1 ;;
    esac
  '';
in
runCommand "duna-run-or-raise-test" { nativeBuildInputs = [ fakeNiri ]; } ''
  export LOG="$TMPDIR/log" WINDOWS="$TMPDIR/windows.json"

  expect() {
    local name=$1 windows=$2 want=$3
    echo "$windows" > "$WINDOWS"
    : > "$LOG"
    ${runOrRaise}/bin/run-or-raise emacs sh -c 'echo spawn >> "$LOG"'
    got=$(cat "$LOG")
    if [ "$got" != "$want" ]; then
      echo "$name: want '$want', got '$got'" >&2
      exit 1
    fi
  }

  expect "focuses the open window of the app" \
    '[{"id":1,"app_id":"foot","is_floating":false},{"id":2,"app_id":"emacs","is_floating":false}]' \
    "focus 2"
  expect "spawns the app when none is open" \
    '[{"id":1,"app_id":"foot","is_floating":false}]' \
    "spawn"
  expect "ignores floating windows of the app" \
    '[{"id":3,"app_id":"emacs","is_floating":true}]' \
    "spawn"

  touch $out
''
