{ pkgs, lib, ... }:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
  l-dict = sources.skkdict.src + /SKK-JISYO.L;
  yaskkserv2 = pkgs.callPackage ./yaskkserv2.nix { };
  make-dict = lib.getExe' yaskkserv2 "yaskkserv2_make_dictionary";
  dict = pkgs.runCommand "yaskkserv2_dictionary" { } ''
    exec ${make-dict} --utf8 --dictionary-filename=$out ${l-dict}
  '';
in
{
  launchd = {
    agents = {
      yaskkserv2 = {
        enable = true;
        config = {
          Program = lib.getExe' yaskkserv2 "yaskkserv2";
          ProgramArguments = [
            "--google-japanese-input=disable"
            dict.outPath
          ];
          RunAtLoad = true;
        };
      };
    };
  };
}
