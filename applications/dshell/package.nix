{
  coreutils,
  devcontainer,
  docker-client,
  docker-credential-helpers,
  git,
  jq,
  writeShellApplication,
}:
writeShellApplication {
  name = "dshell";
  runtimeInputs = [
    coreutils
    devcontainer
    docker-client
    docker-credential-helpers
    git
    jq
  ];
  text = builtins.readFile ./script.sh;
}
