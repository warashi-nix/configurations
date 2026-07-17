{ pkgs, ... }: {
  home = {
    packages = [
      pkgs.lima
      pkgs.podman
    ];
  };
}
