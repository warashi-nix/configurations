{
  lib,
  runCommand,
  athena,
  workbench,
}:
let
  macHome = athena.home-manager.users.warashi;
  linuxHome = workbench.home-manager.users.warashi;
  tests = lib.runTests {
    test-mac-selects-podman = {
      expr = macHome.warashi.chelly.settings.container_cmd or null;
      expected = "podman";
    };
    test-darwin-installs-podman-with-nix = {
      expr = lib.any (package: (package.pname or "") == "podman") macHome.home.packages;
      expected = true;
    };
    test-linux-does-not-install-podman-in-home = {
      expr = lib.any (package: (package.pname or "") == "podman") linuxHome.home.packages;
      expected = false;
    };
    test-mac-does-not-install-podman-with-homebrew = {
      expr = lib.elem "podman" (map (brew: brew.name) athena.homebrew.brews);
      expected = false;
    };
    test-mac-keeps-container = {
      expr = lib.elem "container" (map (brew: brew.name) athena.homebrew.brews);
      expected = true;
    };
    test-mac-shares-all-caches = {
      expr = lib.all (mount: lib.elem mount macHome.warashi.chelly.settings.additional_mounts) [
        "chelly-nix:/nix"
        "go-cache:/home/warashi/.cache/go-build"
        "go-mod:/home/warashi/go/pkg/mod"
        "nix-cache:/home/warashi/.cache/nix"
      ];
      expected = true;
    };
    test-mac-mounts-materialized-git-ignore = {
      expr = lib.filter (
        mount: lib.hasSuffix ":/home/warashi/.config/git/ignore" mount
      ) macHome.warashi.chelly.settings.additional_mounts;
      expected = [ "${macHome.xdg.dataHome}/chelly/git-ignore:/home/warashi/.config/git/ignore" ];
    };
    test-mac-copies-git-ignore-on-activation = {
      expr = macHome.home.activation ? chelly-git-ignore;
      expected = true;
    };
    test-mac-installs-read-only-git-ignore = {
      expr = lib.hasInfix "/bin/install -D -m 0444" macHome.home.activation.chelly-git-ignore.data;
      expected = true;
    };
    test-remote-build-uses-dockerfile-source = {
      expr = lib.elem "--file=${macHome.warashi.chelly.dockerfile}" macHome.warashi.chelly.runtime_options.podman.build;
      expected = true;
    };
    test-linux-keeps-git-ignore-mount = {
      expr = lib.filter (
        mount: lib.hasSuffix ":/home/warashi/.config/git/ignore" mount
      ) linuxHome.warashi.chelly.settings.additional_mounts;
      expected = [ "${linuxHome.xdg.configHome}/git/ignore:/home/warashi/.config/git/ignore" ];
    };
    test-linux-does-not-copy-git-ignore = {
      expr = linuxHome.home.activation ? chelly-git-ignore;
      expected = false;
    };
    test-linux-keeps-host-store = {
      expr = linuxHome.warashi.chelly.nix-store;
      expected = "host";
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "chelly-config-check" { } ''
  touch "$out"
''
