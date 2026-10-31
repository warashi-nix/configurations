{
  lib,
  callPackage,
  runCommand,
  writeShellScriptBin,
}:
let
  sessionMessaging = callPackage ./session-messaging.nix { };
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
  anchor = (callPackage ./session-messaging.nix { podman = fakePodman; }).anchor;
  tests = lib.runTests {
    # chelly は pid namespace が private でないと podman に拒まれる --init を外し、
    # 外した分の孤児の回収は anchor の --init に任せる。
    test-agents-join-anchor-without-own-init = {
      expr = {
        pid = lib.filter (lib.hasPrefix "--pid=") sessionMessaging.runArgs;
        inherit (sessionMessaging) settings;
      };
      expected = {
        pid = [ "--pid=container:chelly-pid" ];
        settings.init = false;
      };
    };
    # Claude Code は socket を $XDG_RUNTIME_DIR/cc-socks に置く。入れ子の podman も
    # $XDG_RUNTIME_DIR に状態を置くので、runtime dir はコンテナごとに分け、cc-socks だけを共有する。
    test-agents-share-only-socket-directory = {
      expr = lib.filter (arg: !(lib.hasPrefix "--pid=" arg)) sessionMessaging.runArgs;
      expected = [
        "--env=XDG_RUNTIME_DIR=/run/chelly"
        "--tmpfs=/run/chelly:rw,mode=0700,U"
        "--volume=chelly-messaging:/run/chelly/cc-socks:U"
      ];
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "chelly-session-messaging-check" { } ''
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
