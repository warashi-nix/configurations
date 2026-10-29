{
  lib,
  stdenvNoCC,
  bash,
  coreutils,
  curl,
  jq,
  python3,
  makeWrapper,
}:
let
  runtimePath = lib.makeBinPath [
    coreutils
    curl
    jq
  ];
in
stdenvNoCC.mkDerivation {
  pname = "slack-notify";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    bash
    coreutils
    curl
    jq
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
    install -Dm755 slack-notify.sh "$out/libexec/slack-notify/slack-notify.sh"
    makeWrapper ${bash}/bin/bash "$out/bin/slack-notify" \
      --add-flags "$out/libexec/slack-notify/slack-notify.sh" \
      --prefix PATH : ${runtimePath}
    runHook postInstall
  '';

  meta = {
    description = "Post a message to a Slack Incoming Webhook whose URL is read from a file";
    license = lib.licenses.cc0;
    mainProgram = "slack-notify";
    platforms = lib.platforms.all;
  };
}
