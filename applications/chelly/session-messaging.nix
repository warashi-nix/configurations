# 別のコンテナの Claude Code 同士でセッション間メッセージを届ける。
#
# agent のコンテナを 1 つの pid namespace に入れる。Claude Code はセッションを
# ~/.claude/sessions/<pid>.json に pid だけをキーに登録するので、コンテナごとの
# namespace では pid が重なり、claude-state を共有する別のセッションの登録を上書きする。
#
# namespace は常駐する anchor コンテナが持つ。pod は uidmap と --userns をコンテナ側に
# 書けず、--pid=host は本人のプロセスの cmdline が agent に見える。止まった anchor は
# 参加するコンテナの起動時に podman が起こし直すので、無いときだけ作ればよい。
#
# Claude Code は socket を $XDG_RUNTIME_DIR/cc-socks に置き、同じディレクトリの socket からの
# 返信を受け付ける。入れ子の podman も $XDG_RUNTIME_DIR に libpod や crun の状態を置くので、
# runtime dir はコンテナごとの tmpfs にし、cc-socks だけを named volume で共有する。
# どちらも U でコンテナのユーザーの所有にする。Claude Code は自分以外が所有する置き場を拒む。
{
  podman,
  writeShellApplication,
}:
let
  name = "chelly-pid";
  runtimeDir = "/run/chelly";
in
{
  runArgs = [
    "--pid=container:${name}"
    "--env=XDG_RUNTIME_DIR=${runtimeDir}"
    "--tmpfs=${runtimeDir}:rw,mode=0700,U"
    "--volume=chelly-messaging:${runtimeDir}/cc-socks:U"
  ];
  # podman は private でない pid namespace に --init を入れられない。孤児の回収は
  # namespace の PID 1 になる anchor の --init が引き受ける。
  settings.init = false;
  anchor = writeShellApplication {
    name = "chelly-pid-anchor";
    runtimeInputs = [ podman ];
    text = ''
      if podman container exists ${name}; then
        exit 0
      fi
      if ! podman image exists chelly:latest; then
        exit 0
      fi
      if podman run --detach --init --name ${name} --network=none --log-driver=none \
        --entrypoint=sleep chelly:latest infinity >/dev/null; then
        exit 0
      fi
      podman container exists ${name}
    '';
  };
}
