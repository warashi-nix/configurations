{
  lib,
  runCommand,
  systems,
}:
let
  # 外部スキーマのキーを写しているため、外部の命名に従う option。
  externalNames = [
    # chelly の config.toml の runtime_options
    "warashi.chelly.runtime_options"
  ];

  # home-manager の option の loc は home-manager.users.<name> から始まるため、その分を落とす。
  scopes =
    system:
    [
      {
        options = system.options;
        prefixLength = 0;
      }
    ]
    ++ lib.mapAttrsToList (_: user: {
      options = user.configuration.options;
      prefixLength = 3;
    }) system.options.home-manager.users.valueMeta.attrs;

  scopePaths =
    scope:
    map (option: lib.drop scope.prefixLength option.loc) (
      lib.collect lib.isOption (scope.options.warashi or { })
    );

  paths = lib.unique (lib.concatMap (system: lib.concatMap scopePaths (scopes system)) systems);

  # warashi.<モジュール名> はディレクトリ名やプログラム名に合わせて kebab-case、
  # その下のフィールドは nixpkgs の option と並べて書くため camelCase にする。
  isCamelCase = name: builtins.match "[a-z][a-zA-Z0-9]*" name != null;

  violations = lib.filter (
    path:
    !(lib.elem (lib.concatStringsSep "." path) externalNames)
    && !(lib.all isCamelCase (lib.drop 2 path))
  ) paths;
in
assert lib.assertMsg (violations == [ ]) ''
  warashi.<module> の下の option 名は camelCase にする (外部スキーマを写すものは checks/option-naming.nix の externalNames に足す):
  ${lib.concatMapStringsSep "\n" (path: "  " + lib.concatStringsSep "." path) violations}
'';
runCommand "option-naming-check" { } ''
  touch "$out"
''
