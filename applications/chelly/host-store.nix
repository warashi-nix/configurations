# warashi.chelly.nix-store = "host" の実装。
# ホストの /nix を read-only で見せ、ビルドや substitute はホストの nix-daemon に任せる。
# コンテナは --userns=keep-id なのでホストのソケットに直接つなぐと wheel の
# trusted user として扱われてしまう。そのため本物のソケットは隠し、
# NixOS 側 (warashi.chelly-nix-proxy) が untrusted な別ユーザーで動かす転送用ソケットだけを見せる。
{
  config,
  lib,
  osConfig ? null,
  ...
}:
with lib;
let
  cfg = config.warashi.chelly;
  proxy =
    if osConfig != null && osConfig ? warashi.chelly-nix-proxy then
      osConfig.warashi.chelly-nix-proxy
    else
      null;
in
{
  config = mkIf (cfg.enable && cfg.nix-store == "host") {
    assertions = [
      {
        assertion = proxy != null && proxy.enable;
        message = "warashi.chelly.nix-store = \"host\" には NixOS 側で warashi.chelly-nix-proxy.enable = true が要る";
      }
    ];

    # proxy が無いときは上の assertion が出るので、ここは評価エラーにせず空にしておく。
    warashi.chelly = mkIf (proxy != null) {
      settings.additional_mounts = [
        "/nix:/nix:ro"
        # /nix の中のソケットディレクトリを覆って本物の daemon ソケットを隠す。
        # store = auto はこのパスのソケットを見て daemon 接続を選ぶので NIX_REMOTE は要らない。
        "${proxy.socket-dir}:/nix/var/nix/daemon-socket:ro"
      ];
      # コンテナには ~/.nix-profile が無く、ホストの nix は /run/current-system 経由でしか
      # 見えないため、daemon と同じ版の nix を store path で直接渡して entrypoint が PATH に足す。
      runtime_options.podman.run = [
        "--env=CHELLY_NIX_BIN=${osConfig.nix.package}/bin"
      ];
    };
  };
}
