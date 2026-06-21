{
  stdenv,
  fetchurl,
  callPackage,
  buildNpmPackage,
  nodejs,
  ...
}:
buildNpmPackage (final: {
  pname = "markmap-cli";
  version = "0.18.12";

  src = fetchurl {
    url = "https://registry.npmjs.org/${final.pname}/-/${final.pname}-${final.version}.tgz";
    hash = "sha256-96yqm8hDIwnQGgVn2MO6V6fZqfLFhnUEEC2PDU9vPKU=";
  };

  nativeBuildInputs = [
    nodejs
  ];

  npmDepsHash = "sha256-rSsW8Do9Z3MHDAhNfSHFUK04wAnF3v7lwI0sx3igxM4=";

  dontNpmBuild = true;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';
})
