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

  npmDepsHash = "sha256-eLiNwwIJIl4VnY+nmu0DJ91Hl/RtCGKhcpEGTa/wQT0=";

  dontNpmBuild = true;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';
})
