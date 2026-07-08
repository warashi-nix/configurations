{
  pkgs,
  inputs,
  ...
}:
{
  home = {
    packages = [
      inputs.git-wit.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
