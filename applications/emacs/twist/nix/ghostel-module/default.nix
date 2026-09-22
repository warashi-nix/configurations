{
  lib,
  stdenv,
  zig,
  callPackage,
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

  deps = callPackage ./build.zig.zon.nix { };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ghostel-module";
  inherit version src;

  nativeBuildInputs = [
    zig
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ xcodeShim ];

  # zig 0.16.0 の `zig build --system` は、パス依存 (pkg/*) を持つ ghostty
  # のようなパッケージが farm にあると無限ループする。zon2nix はそうした
  # パッケージを pathDependencyPackages に列挙するので、それらをビルド
  # ルートへコピーして --fork で farm の外から渡すと通る。詳細は zon2nix
  # の README を参照。
  # zon2nix の README は `cp -rsL` (ファイルは symlink) を案内しているが、
  # zig の installHeadersDirectory は kind が .file のエントリしかコピー
  # しないため、ghostty の pkg/simdutf のヘッダが黙って落ちて
  # 'simdutf.h' file not found になる。実体コピーが要る。
  postPatch = lib.concatMapStrings (p: ''
    cp -rL --no-preserve=mode ${deps}/${p} fork-${p}
  '') deps.pathDependencyPackages;

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
    "--system"
    "${deps}"
  ]
  ++ map (p: "--fork=fork-${p}") deps.pathDependencyPackages;

  # darwin stdenv の apple-sdk は xcbuild 製 xcrun を propagate しており
  # PATH 上でシムより先に来る可能性があるため、シムを先頭に固定する
  postConfigure = lib.optionalString stdenv.hostPlatform.isDarwin ''
    export PATH="${xcodeShim}/bin:$PATH"
  '';

  meta = {
    description = "Native module for ghostel, built from the same source as the elisp package";
    platforms = lib.platforms.unix;
  };
})
