{
  lib,
  stdenvNoCC,
  git,
  python3,
  makeWrapper,
}:

stdenvNoCC.mkDerivation {
  pname = "git-check-new-ignored";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
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
    makeWrapper ${python3}/bin/python3 "$out/bin/git-check-new-ignored" \
      --add-flags "$out/libexec/git-check-new-ignored/git_check_new_ignored.py" \
      --prefix PATH : ${lib.makeBinPath [ git ]}
    runHook postInstall
  '';

  meta = {
    description = "Check incoming Git history for newly tracked ignored files";
    license = lib.licenses.cc0;
    mainProgram = "git-check-new-ignored";
    platforms = lib.platforms.all;
  };
}
