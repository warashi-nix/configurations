{ inputs, ... }:
{
  imports = [
    # keep-sorted start
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    # keep-sorted end
  ];
}
