nix := "nom"
os := os()
arch := arch()
host := `uname -n`

system := if os() == "macos" {
  "aarch64-darwin"
} else if os() == "linux" {
  if arch() == "x86_64" { "x86_64-linux" }
  else if arch() == "aarch64" { "aarch64-linux" }
  else { error("Unsupported architecture: " + arch()) }
} else { error("Unsupported OS: " + os()) }

# ===== レシピ =====

_default:
  @just --list

# デフォルト build （マシン自身）
build: (build-for host)

# デフォルト switch （マシン自身）
switch: (switch-for host)

emacs-lock:
  nix run .#lock --impure && nix flake update my-emacs-pkgs

emacs-update:
  cd ./applications/emacs/twist/lock && nix flake update && cd - && nix flake update my-emacs-pkgs

# Emacs ローカルパッケージの ert を手元の Emacs で回す
# nix build を挟まないのは、1 ファイル直すたびの往復を短く保つため。
# CI との一致は .#checks 側が担保する。
test-emacs PACKAGE='':
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{ justfile_directory() }}/applications/emacs/twist/packages"
  status=0
  for dir in {{ if PACKAGE == "" { "*" } else { PACKAGE } }}; do
    [ -f "$dir/$dir-test.el" ] || continue
    echo "==> $dir"
    ( cd "$dir" && "${EMACS:-emacs}" -Q --batch -L . -l "$dir-test.el" -f ert-run-tests-batch-and-exit ) || status=1
  done
  exit $status

# マシンを指定しての build
build-for HOST:
  just {{ if os() == "macos" { "_darwin-rebuild-for" } else { "_nixos-rebuild-for" } }} {{HOST}}

# マシンを指定しての switch
switch-for HOST:
  just {{ if os() == "macos" { "_darwin-rebuild-switch-for" } else { "_nixos-rebuild-switch-for" } }} {{HOST}}

_darwin-rebuild-for HOST:
  {{nix}} build --accept-flake-config --keep-going --no-link --show-trace --system {{system}} .#darwinConfigurations.{{HOST}}.system

_darwin-rebuild-switch-for HOST:
  sudo darwin-rebuild switch --flake .#{{HOST}}

_nixos-rebuild-for HOST:
  {{nix}} build --accept-flake-config --keep-going --no-link --show-trace --system {{system}} .#nixosConfigurations.{{HOST}}.config.system.build.toplevel

_nixos-rebuild-switch-for HOST:
  sudo nixos-rebuild switch --accept-flake-config --flake .#{{HOST}}
