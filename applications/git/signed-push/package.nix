{
  lib,
  stdenvNoCC,
  bash,
  git,
  openssh,
  python3,
  makeWrapper,
}:

stdenvNoCC.mkDerivation {
  pname = "require-signed-push";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    bash
    git
    openssh
    python3
  ];

  doCheck = true;

  checkPhase = ''
    runHook preCheck
    export TEST_TMPDIR="$TMPDIR/tests"
    mkdir -p "$TEST_TMPDIR"
    ${python3}/bin/python3 -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    makeWrapper ${bash}/bin/bash "$out/bin/require-signed-push" \
      --add-flags ${placeholder "out"}/libexec/require-signed-push.sh \
      --prefix PATH : ${lib.makeBinPath [ git ]}
    install -Dm755 require-signed-push.sh "$out/libexec/require-signed-push.sh"
    runHook postInstall
  '';

  meta = {
    description = "pre-push hook that rejects commits without a signature";
    license = lib.licenses.cc0;
    mainProgram = "require-signed-push";
    platforms = lib.platforms.all;
  };
}
