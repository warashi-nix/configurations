{ lib, buildGoModule }:

buildGoModule {
  pname = "chelly-go-proxy";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "go" || file.name == "go.mod") ./.;
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "GOPROXY that serves only allowed modules to isolated Chelly agents";
    license = lib.licenses.cc0;
    mainProgram = "chelly-go-proxy";
    platforms = lib.platforms.all;
  };
}
