{ config, ... }:
let
  overrideArg =
    originalFn: modifyFn: originalArg:
    originalFn (modifyFn originalArg);
in
{
  # nixpkgs の integrations-core は pname が Python パッケージ名と一致せず pythonMetadataCheckPhase で失敗するため、upstream で直るまで無効化する
  nixpkgs.overlays = [
    (final: prev: {
      datadog-integrations-core =
        extras:
        (prev.datadog-integrations-core extras).override (args: {
          python3Packages = args.python3Packages // {
            buildPythonPackage = overrideArg args.python3Packages.buildPythonPackage (
              attrs: attrs // { dontCheckPythonMetadata = true; }
            );
          };
        });
    })
  ];

  sops.secrets.hestia-datadog-apikey = {
    owner = "datadog";
    restartUnits = [ "datadog-agent.service" ];
  };
  services.datadog-agent = {
    enable = true;
    apiKeyFile = config.sops.secrets.hestia-datadog-apikey.path;
    site = "ap1.datadoghq.com";
  };
}
