# 別のコンテナの Claude Code 同士でセッション間メッセージを届ける。
#
# agent のコンテナを 1 つの pid namespace に入れる。Claude Code はセッションを
# ~/.claude/sessions/<pid>.json に pid だけをキーに登録するので、コンテナごとの
# namespace では pid が重なり、claude-state を共有する別のセッションの登録を上書きする。
#
# namespace は常駐する anchor コンテナが持つ。pod は uidmap と --userns をコンテナ側に
# 書けず、--pid=host は本人のプロセスの cmdline が agent に見える。止まった anchor は
# 参加するコンテナの起動時に podman が起こし直すので、無いときだけ作ればよい。
{
  podman,
  writeShellApplication,
}:
let
  name = "chelly-pid";
in
{
  runArgs = [ "--pid=container:${name}" ];
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
