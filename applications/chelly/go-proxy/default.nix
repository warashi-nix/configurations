# warashi.chelly.goProxy の実装。macOS の専用構成で、許可した private Go module だけを
# コンテナに渡す。
#
# 本人の Git 認証は Mac 側の chelly-go-proxy だけが使い、コンテナには module の中身だけを
# 返す。許可リストは Nix の設定から launchd の引数に焼き込むので、VM に共有した領域から
# agent が書き換えることはできない。
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.chelly.goProxy;
  chellyCfg = config.warashi.chelly;
  port = 3140;
  patterns = concatStringsSep "," cfg.allow;
  package = pkgs.callPackage ./package.nix { };
in
{
  options.warashi.chelly.goProxy.allow = mkOption {
    type = types.listOf types.str;
    default = [ ];
    example = [ "github.com/example/repo" ];
    description = ''
      コンテナに渡す private Go module の path pattern。GOPRIVATE と同じ書式で、
      一致した path の下の module も含む。空なら proxy を動かさない。
    '';
  };

  config = mkIf (chellyCfg.enable && cfg.allow != [ ]) {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin && chellyCfg.dedicated;
        message = "warashi.chelly.goProxy は macOS の専用構成 (warashi.chelly.dedicated) 用";
      }
    ];

    launchd.agents.chelly-go-proxy = {
      enable = true;
      config = {
        ProgramArguments = [
          (getExe package)
          "-listen"
          "127.0.0.1:${toString port}"
          "-allow"
          patterns
          "-cache-dir"
          "${config.xdg.cacheHome}/chelly-go-proxy"
          "-go"
          "${config.programs.go.package}/bin/go"
        ];
        EnvironmentVariables = {
          # git が本人の設定 (gh の credential helper) を読むのに要る。
          HOME = config.home.homeDirectory;
          # credential helper を `!gh auth git-credential` のように PATH 頼みで書いた設定でも
          # 認証できるよう、gh も入れる。
          PATH = "${config.programs.git.package}/bin:${config.programs.gh.package}/bin:/usr/bin:/bin";
        };
        KeepAlive = true;
        RunAtLoad = true;
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/chelly-go-proxy.log";
      };
    };

    # GOPRIVATE は GONOPROXY の既定になり、private module が proxy を迂回して認証の無い
    # direct 取得に行くので渡さない。許可しない path は proxy が 404 を返し、公開 module は
    # 次の proxy.golang.org から取る。
    warashi.chelly.runtime_options.podman.run = [
      "--env=GONOSUMDB=${patterns}"
      "--env=GOPROXY=http://host.containers.internal:${toString port},https://proxy.golang.org"
    ];
  };
}
