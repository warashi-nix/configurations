{
  lib,
  callPackage,
  runCommand,
  writeShellScriptBin,
}:
let
  sharedPid = callPackage ./shared-pid.nix { };
  # podman の代わりに、呼ばれた引数を記録し、状態ファイルに従って答える。
  fakePodman = writeShellScriptBin "podman" ''
    echo "$*" >>"$STATE/calls"
    case "$1 $2" in
      "container exists") test -e "$STATE/container" ;;
      "image exists") test -e "$STATE/image" ;;
      run*)
        if [ -e "$STATE/race" ]; then touch "$STATE/container"; exit 125; fi
        test -e "$STATE/run-fails" && exit 125
        touch "$STATE/container"
        ;;
    esac
  '';
  anchor = (callPackage ./shared-pid.nix { podman = fakePodman; }).anchor;
  tests = lib.runTests {
    # chelly は pid namespace が private でないと podman に拒まれる --init を外し、
    # 外した分の孤児の回収は anchor の --init に任せる。
    test-agents-join-anchor-without-own-init = {
      expr = {
        inherit (sharedPid) runArgs settings;
      };
      expected = {
        runArgs = [ "--pid=container:chelly-pid" ];
        settings.init = false;
      };
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "chelly-shared-pid-check" { } ''
  anchor=${lib.getExe anchor}

  setup() { STATE=$(mktemp -d); export STATE; touch "$STATE/calls"; for flag in "$@"; do touch "$STATE/$flag"; done; }
  runs() { grep -c '^run ' "$STATE/calls" || true; }

  # 既にあれば作り直さない。作り直すと参加済みのコンテナと namespace が分かれる。
  setup container image
  "$anchor"
  test "$(runs)" = 0

  # image が無ければ chelly run 自身が失敗するので、build の前は何もせず通す。
  setup
  "$anchor"
  test "$(runs)" = 0

  setup image
  "$anchor"
  grep -q '^run --detach --init --name chelly-pid .*chelly:latest' "$STATE/calls"

  # 同時に起動した別の chelly が先に作っていれば成功とみなす。
  setup image race
  "$anchor"

  setup image run-fails
  if "$anchor"; then
    echo "anchor ignored a failed podman run" >&2
    exit 1
  fi

  touch "$out"
''
