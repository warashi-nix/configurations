{ pkgs, lib, ... }:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
  l-dict = sources.skkdict.src + /SKK-JISYO.L;
  yaskkserv2 = pkgs.callPackage ./yaskkserv2.nix { };
  make-dict = lib.getExe' yaskkserv2 "yaskkserv2_make_dictionary";
  dict = pkgs.runCommand "yaskkserv2_dictionary" { } ''
    exec ${make-dict} --dictionary-filename=$out '${l-dict}'
  '';
in
{
  systemd = {
    user = {
      services = {
        yaskkserv2 = {
          Unit = {
            Description = "SKK Server";
          };
          Service = {
            ExecStart = "${lib.getExe' yaskkserv2 "yaskkserv2"} --no-daemonize --google-japanese-input=disable ${dict.outPath}";
            Restart = "always";
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };
    };
  };
  launchd = {
    agents = {
      yaskkserv2 = {
        enable = true;
        config = {
          Program = lib.getExe' yaskkserv2 "yaskkserv2";
          ProgramArguments = [
            "--no-daemonize"
            "--google-japanese-input=disable"
            dict.outPath
          ];
          RunAtLoad = true;
        };
      };
    };
  };
}
