{
  lib,
  stdenvNoCC,
  bash,
  git,
  python3,
  makeWrapper,
}:

stdenvNoCC.mkDerivation {
  pname = "git-check-new-ignored";
  version = "0.2.0";

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
    export XDG_CONFIG_HOME="$HOME/.config"
    export TEST_TMPDIR="$TMPDIR/tests"
    mkdir -p "$HOME" "$TEST_TMPDIR"
    ${python3}/bin/python3 -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 git_check_new_ignored.py \
      "$out/libexec/git-check-new-ignored/git_check_new_ignored.py"
    install -Dm755 chelly-handoff.sh \
      "$out/libexec/git-check-new-ignored/chelly-handoff.sh"
    makeWrapper ${python3}/bin/python3 "$out/bin/git-check-new-ignored" \
      --add-flags "$out/libexec/git-check-new-ignored/git_check_new_ignored.py" \
      --prefix PATH : ${lib.makeBinPath [ git ]}
    makeWrapper ${bash}/bin/bash "$out/bin/chelly-handoff" \
      --add-flags "$out/libexec/git-check-new-ignored/chelly-handoff.sh" \
      --prefix PATH : "$out/bin:${lib.makeBinPath [ git ]}"
    runHook postInstall
  '';

  meta = {
    description = "Receive and validate Git handoffs from isolated Chelly agents";
    license = lib.licenses.cc0;
    mainProgram = "git-check-new-ignored";
    platforms = lib.platforms.all;
  };
}
