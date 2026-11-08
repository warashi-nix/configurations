{ lib, buildGoModule }:

buildGoModule {
  pname = "ud-co2s-exporter";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "go" || file.name == "go.mod") ./.;
  };

  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta = {
    description = "Prometheus exporter for the IO-DATA UD-CO2S CO2 sensor";
    license = lib.licenses.cc0;
    mainProgram = "ud-co2s-exporter";
    platforms = lib.platforms.linux;
  };
}
