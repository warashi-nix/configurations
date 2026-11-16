# コンテナ内の ~/ghq 配下には chelly-handoff の clone 単体だけを mount する。
# ~/ghq の親を mount すると、コンテナ内で ghq get した clone が handoff の管理外のまま
# 専用領域に残る。macOS の dedicated.nix と NixOS の chelly-agent がこの値を読む。
{ lib, ... }:
with lib;
{
  options.warashi.chelly.handoffRepos = mkOption {
    type = types.attrsOf (types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*");
    default = { };
    example = {
      "github.com/acme/pkm" = "main";
    };
    description = ''
      コンテナ内の ~/ghq 配下に見せる chelly-handoff の clone。
      キーは ~/ghq からの path、値は handoff の ID。clone は専用領域の `<キー>/<ID>` にある。
    '';
  };

  options.warashi.chelly.handoffSessionRepo = mkOption {
    type = types.str;
    description = ''
      `chelly --handoff NAME run` を cwd に関わらず起動する clone の、handoffRepos のキー。
    '';
  };

  # 本人の CLAUDE.md が指す path で、brainium の handoff clone を使う。
  config.warashi.chelly.handoffRepos."github.com/Warashi/brainium" = "brainium";
  # 横断作業の計画は brainium の task で立てる。
  config.warashi.chelly.handoffSessionRepo = "github.com/Warashi/brainium";
}
