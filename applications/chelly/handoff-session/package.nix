{
  lib,
  stdenvNoCC,
  bash,
  coreutils,
  findutils,
  git,
  makeWrapper,
  podman,
  python3,
  callPackage,
  chelly,
  # 専用領域。chelly-handoff の root と一致させる。
  workspaces,
  # chelly の設定の additional_mounts。CHELLY_ADDITIONAL_MOUNTS は設定を置き換えるので、
  # 集めた clone を足すときはこれに続ける。
  additionalMounts ? [ ],
  # 設定で常に mount する clone。同じ destination に二重に mount しないよう集めない。
  fixedSources ? [ ],
  # --handoff のときに起動する clone。計画を立てる brainium の clone を指す。
  sessionDirectory,
}:
let
  chellyHandoff = callPackage ../../git/handoff/package.nix { inherit workspaces; };
in
stdenvNoCC.mkDerivation {
  pname = "chelly-handoff-session";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    bash
    git
    python3
  ];

  doCheck = true;

  checkPhase = ''
    runHook preCheck
    export HOME="$TMPDIR/home"
    export TEST_TMPDIR="$TMPDIR/tests"
    mkdir -p "$HOME" "$TEST_TMPDIR"
    # テストは chelly-handoff の id を実物で呼ぶ。
    export CHELLY_HANDOFF_SCRIPT=${../../git/handoff/chelly-handoff.sh}
    ${python3}/bin/python3 -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 handoff-session.sh "$out/libexec/chelly-handoff-session/handoff-session.sh"
    makeWrapper ${bash}/bin/bash "$out/bin/chelly-handoff-session" \
      --add-flags "$out/libexec/chelly-handoff-session/handoff-session.sh" \
      --prefix PATH : ${
        lib.makeBinPath [
          chellyHandoff
          coreutils
          findutils
          podman
        ]
      } \
      --set HANDOFF_SESSION_WORKSPACES ${lib.escapeShellArg workspaces} \
      --set HANDOFF_SESSION_MOUNTS ${lib.escapeShellArg (lib.concatStringsSep "," additionalMounts)} \
      --set HANDOFF_SESSION_FIXED ${lib.escapeShellArg (lib.concatStringsSep "\n" fixedSources)} \
      --set HANDOFF_SESSION_CHELLY ${lib.getExe' chelly "chelly"} \
      --set HANDOFF_SESSION_DIRECTORY ${lib.escapeShellArg sessionDirectory}
    runHook postInstall
  '';

  meta = {
    description = "Start chelly with every handoff clone sharing a name";
    mainProgram = "chelly-handoff-session";
    platforms = lib.platforms.all;
  };
}
