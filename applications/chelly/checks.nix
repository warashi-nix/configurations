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
    testMacSelectsPodman = {
      expr = macHome.warashi.chelly.settings.container_cmd or null;
      expected = "podman";
    };
    testMacInstallsPodmanAlongsideContainer = {
      expr = lib.all (name: lib.elem name (map (brew: brew.name) athena.homebrew.brews)) [
        "container"
        "podman"
      ];
      expected = true;
    };
    testMacSharesAllCaches = {
      expr = lib.all (mount: lib.elem mount macHome.warashi.chelly.settings.additional_mounts) [
        "chelly-nix:/nix"
        "go-cache:/home/warashi/.cache/go-build"
        "go-mod:/home/warashi/go/pkg/mod"
        "nix-cache:/home/warashi/.cache/nix"
      ];
      expected = true;
    };
    testMacMountsMaterializedGitIgnore = {
      expr = lib.filter (
        mount: lib.hasSuffix ":/home/warashi/.config/git/ignore" mount
      ) macHome.warashi.chelly.settings.additional_mounts;
      expected = [ "${macHome.xdg.dataHome}/chelly/git-ignore:/home/warashi/.config/git/ignore" ];
    };
    testMacCopiesGitIgnoreOnActivation = {
      expr = macHome.home.activation ? chelly-git-ignore;
      expected = true;
    };
    testRemoteBuildUsesDockerfileSource = {
      expr = lib.elem "--file=${macHome.warashi.chelly.dockerfile}" macHome.warashi.chelly.runtime_options.podman.build;
      expected = true;
    };
    testLinuxKeepsGitIgnoreMount = {
      expr = lib.filter (
        mount: lib.hasSuffix ":/home/warashi/.config/git/ignore" mount
      ) linuxHome.warashi.chelly.settings.additional_mounts;
      expected = [ "${linuxHome.xdg.configHome}/git/ignore:/home/warashi/.config/git/ignore" ];
    };
    testLinuxDoesNotCopyGitIgnore = {
      expr = linuxHome.home.activation ? chelly-git-ignore;
      expected = false;
    };
    testLinuxKeepsHostStore = {
      expr = linuxHome.warashi.chelly.nix-store;
      expected = "host";
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "chelly-config-check" { } ''
  touch "$out"
''
