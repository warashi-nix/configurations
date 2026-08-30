{
  lib,
  stdenv,
  zig,
  callPackage,
  runCommand,
  writeShellScriptBin,
  symlinkJoin,
  src,
  version,
}:
let
  # macOS の Nix サンドボックスには Xcode がないが、ghostty の
  # pkg/apple-sdk (ghostty-vt がビルドグラフ構築時に辿る pkg/*) は zig の
  # LibCInstallation.findNative 経由で `xcode-select --print-path` と
  # `xcrun --sdk <名前> --show-sdk-path` を実行して SDK を探すため、その
  # ままでは DarwinSdkNotFound で panic する。xcbuild では解決できない:
  # ghostty の build.zig は darwin ターゲットだと XCFramework 用に iOS /
  # iOS Simulator 向けのグラフも無条件に構築し、そこで要求される iphoneos
  # SDK は CLT 由来の Nix apple-sdk に存在しないため。
  # そこで --sdk の値を無視して $SDKROOT (apple-sdk setup hook が設定する
  # macOS SDK) を返すシムで両コマンドを置き換える。iOS 向けステップは
  # グラフに乗るだけで実行されない。
  xcodeShim = symlinkJoin {
    name = "xcode-shim";
    paths = [
      (writeShellScriptBin "xcode-select" ''
        [ -n "''${SDKROOT:-}" ] || {
          echo "xcode-select shim: SDKROOT is not set" >&2
          exit 1
        }
        echo "$SDKROOT"
      '')
      (writeShellScriptBin "xcrun" ''
        [ -n "''${SDKROOT:-}" ] || {
          echo "xcrun shim: SDKROOT is not set" >&2
          exit 1
        }
        case " $* " in
          *" --show-sdk-path "*) echo "$SDKROOT" ;;
          *)
            echo "xcrun shim: unsupported invocation: xcrun $*" >&2
            exit 1
            ;;
        esac
      '')
    ];
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ghostel-module";
  inherit version src;

  nativeBuildInputs = [
    zig
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ xcodeShim ];

  deps = callPackage ./build.zig.zon.nix {
    name = "${finalAttrs.pname}-cache-${finalAttrs.version}";
    # linkFarm の既定は store への symlink を張るだけなので、後段で
    # tar に食わせるために実体を持つツリーにする。-L は付けない:
    # ツリー内の symlink を実体化するとパッケージの内容が変わり、zig の
    # ハッシュ検証が mismatch で落ちる。
    linkFarm =
      name: entries:
      runCommand name { } ''
        mkdir -p $out
        ${lib.concatMapStringsSep "\n" (e: ''
          cp -r ${e.path} $out/${e.name}
        '') entries}
      '';
  };

  # zon2nix が用意するのは展開済みのツリーだが、zig 0.16 のグローバル
  # キャッシュ p/ は <hash>.tar.gz を置く形式に変わっており、展開済み
  # ディレクトリを置いても認識されずネットワーク取得に走る。そこで
  # <hash>/ を root に持つ tar.gz へ詰め直す。zig は展開後の内容から
  # ハッシュを検証するので、tar のバイト列が upstream と一致する必要は
  # ない。
  # zon2nix が案内するもう一方の方法 (--system で p/ 相当のディレクトリを
  # 渡す) は使えない: ghostty のようにパス依存 (pkg/*) を含むパッケージを
  # --system で渡すと zig build が出力なしで無限ループする
  # (https://codeberg.org/ziglang/zig/issues/32121)。
  # --hard-dereference は外せない: auto-optimise-store (linux で有効) が
  # deps のツリー内で同一内容のファイルを hardlink にまとめるため、素の
  # tar は 2 個目以降を type '1' (hardlink) エントリとして記録するが、zig
  # の tar reader は type '1' を扱えず unable to unpack tarball で落ちる。
  # 残りのフラグは tar の出力を決定的にするためのもので、正しさには影響
  # しない。
  zigCache = runCommand "ghostel-module-zig-cache-${finalAttrs.version}" { } ''
    mkdir -p "$out"
    for dir in ${finalAttrs.deps}/*; do
      name="$(basename "$dir")"
      tar --hard-dereference \
        --sort=name --owner=0 --group=0 --numeric-owner --mtime=@1 \
        -czf "$out/$name.tar.gz" -C ${finalAttrs.deps} "$name"
    done
  '';

  # hook のデフォルト (--release=safe) は使えない: ReleaseSafe だと
  # src/posix.h の translate-c が zig 同梱 glibc の fortify ヘッダ
  # (fcntl2.h の __open_missing_mode 等) を展開して落ちる。upstream CI と
  # 同じ ReleaseFast なら通る。-Dcpu=baseline はビルドマシンの CPU に
  # 最適化させないため (hook の既定値と同じだが、既定を切ると消えるので
  # 明示する)。
  dontSetZigDefaultFlags = true;
  zigBuildFlags = [
    "-Dcpu=baseline"
    "-Doptimize=ReleaseFast"
  ];

  postConfigure = ''
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
    cp ${finalAttrs.zigCache}/*.tar.gz "$ZIG_GLOBAL_CACHE_DIR/p/"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  ''
  # darwin stdenv の apple-sdk は xcbuild 製 xcrun を propagate しており
  # PATH 上でシムより先に来る可能性があるため、シムを先頭に固定する
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    export PATH="${xcodeShim}/bin:$PATH"
  '';

  meta = {
    description = "Native module for ghostel, built from the same source as the elisp package";
    platforms = lib.platforms.unix;
  };
})
