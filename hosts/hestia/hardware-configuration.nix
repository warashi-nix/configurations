{ lib, ... }:
{
  # facter.json は nixos-anywhere がインストール時に生成するので、それまでは評価だけ通す。
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;
}
