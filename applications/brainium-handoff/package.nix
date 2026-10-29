{
  lib,
  stdenvNoCC,
  git,
  python3,
  makeWrapper,
}:
stdenvNoCC.mkDerivation {
  pname = "brainium-handoff-pending";
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
    export TEST_TMPDIR="$TMPDIR/tests"
    mkdir -p "$HOME" "$TEST_TMPDIR"
    ${python3}/bin/python3 -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 brainium_handoff_pending.py \
      "$out/libexec/brainium-handoff/brainium_handoff_pending.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/brainium-handoff-pending" \
      --add-flags "-I $out/libexec/brainium-handoff/brainium_handoff_pending.py" \
      --prefix PATH : ${lib.makeBinPath [ git ]}
    runHook postInstall
  '';

  meta = {
    description = "List brainium handoff requests that the owner has not taken in yet";
    license = lib.licenses.cc0;
    mainProgram = "brainium-handoff-pending";
    platforms = lib.platforms.all;
  };
}
