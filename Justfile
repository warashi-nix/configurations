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
# <pkg>-contract-test.el を拾わないのは、上流を実物として require するため
# 素の Emacs では成立しないから。ファイル名を完全一致で見ているので、
# 除外は自動的に効く。契約テストは .#checks 側だけで走る。
test-emacs PACKAGE='':
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{ justfile_directory() }}/applications/emacs/twist/packages"
  # 兄弟パッケージも load-path に入れる。パッケージ間に依存があるとき
  # (warashi-nskk-map -> warashi-nskk-im)、env 側の古い複製ではなく手元の
  # ソースを読ませるため。
  load_path=()
  for pkg in */; do load_path+=(-L "$PWD/${pkg%/}"); done
  status=0
  for dir in {{ if PACKAGE == "" { "*" } else { PACKAGE } }}; do
    [ -f "$dir/$dir-test.el" ] || continue
    echo "==> $dir"
    ( cd "$dir" && "${EMACS:-emacs}" -Q --batch -L . "${load_path[@]}" -l "$dir-test.el" -f ert-run-tests-batch-and-exit ) || status=1
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

# ghostel のネイティブモジュールが使う zig 依存 (ghostty) の固定を再生成する。
# ghostel の rev が上がっても ghostty の pin が動かなければ内容は変わらない。
# 動いたのに再生成しないと、nix のビルドサンドボックスから依存を引けず失敗する。
emacs-ghostel-zon2nix:
  #!/usr/bin/env bash
  set -euo pipefail
  src="$(nix eval --raw --impure --expr \
    'let lock = builtins.getFlake "path:{{ justfile_directory() }}/applications/emacs/twist/lock"; in lock.inputs.ghostel.outPath')"
  out="{{ justfile_directory() }}/applications/emacs/twist/nix/ghostel-module/build.zig.zon.nix"
  cd "$src"
  zon2nix --16 --nix="$out" build.zig.zon
