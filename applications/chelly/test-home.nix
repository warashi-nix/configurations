# chelly の home-manager モジュールと host の homes/chelly.nix だけを取り込んだ最小構成を
# 評価する。完全な host config は ../../applications 配下の無関係なパッケージ (twist 経由の
# emacs など) まで含み、それらを辿ると Darwin 向け IFD ビルドが要求されて aarch64-linux では
# 失敗する。
{ homeManagerLib, chellyModuleInputs }:
let
  # sops-nix 本体の home-manager モジュールは鍵ソースの assertion を要求するため、
  # ここでは cfg.envfiles が参照する sops.secrets.*.path だけを提供する最小限の
  # スタブに留める。
  sopsSecretsStub =
    { lib, ... }:
    {
      options.sops.secrets = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options.path = lib.mkOption {
                type = lib.types.str;
                default = "/run/secrets/${name}";
              };
            }
          )
        );
        default = { };
      };
    };

  # dedicated.nix は本人の Claude/Copilot の配布 bundle を参照する。最小構成では
  # applications/claude と copilot を取り込まず、bundle の option だけを空の store path で満たす。
  agentBundleStub =
    { lib, pkgs, ... }:
    {
      options.warashi.claude.bundle = lib.mkOption {
        type = lib.types.package;
        default = pkgs.emptyDirectory;
      };
      options.warashi.copilot.bundle = lib.mkOption {
        type = lib.types.package;
        default = pkgs.emptyDirectory;
      };
    };
in
{
  pkgs,
  hostHomeModule,
  extraModules ? [ ],
}:
(homeManagerLib.homeManagerConfiguration {
  inherit pkgs;
  extraSpecialArgs = {
    inputs = chellyModuleInputs;
    # nix-store = "host" (workbench) は host-store.nix が osConfig.warashi.chelly-nix-proxy
    # を要求する。実ホストでは hosts/workbench/chelly.nix が有効にしているものを、
    # NixOS 側を丸ごと評価せずに満たすための最小限のスタブ。
    osConfig = {
      warashi.chelly-nix-proxy = {
        enable = true;
        socket-dir = "/run/chelly-nix";
      };
      nix.package = pkgs.nix;
    };
  };
  modules = [
    sopsSecretsStub
    agentBundleStub
    ./default.nix
    hostHomeModule
    {
      home = {
        username = "warashi";
        homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/warashi" else "/home/warashi";
        stateVersion = "24.11";
      };
    }
  ]
  ++ extraModules;
}).config
