{
  config,
  lib,
  pkgs,
  ...
}:
let
  llama = lib.getExe' pkgs.llama-cpp "llama";
  llama-server = lib.getExe' pkgs.llama-cpp "llama-server";
  state-directory = "${config.xdg.stateHome}/llama-server";
  cache-directory = "${config.xdg.cacheHome}/llama.cpp";
  models = {
    gemma-4-12b-qat = {
      hf-repo = "unsloth/gemma-4-12B-it-qat-GGUF:UD-Q4_K_XL";
      mmproj-auto = false;
      ctx-size = 65536;
      parallel = 1;
      cache-type-k = "q8_0";
      cache-type-v = "q8_0";
      gpu-layers = 999;
      flash-attn = "on";
      spec-type = "draft-mtp";
      spec-draft-n-max = 2;
      temp = "1.0";
      mirostat = 2;
      mirostat-ent = "5.0";
      mirostat-lr = "0.1";
      reasoning = "off";
      sleep-idle-seconds = 900;
      ui = false;
      load-on-startup = false;
    };
    ornith-1-5-9b = {
      hf-repo = "ornith-ai/Ornith-1.5-9B-GGUF:Q6_K";
      ctx-size = 32768;
      parallel = 1;
      cache-type-k = "q8_0";
      cache-type-v = "q8_0";
      gpu-layers = 999;
      flash-attn = "on";
      temp = "0.6";
      top-p = "0.95";
      top-k = 20;
      min-p = "0.0";
      reasoning = "off";
      sleep-idle-seconds = 900;
      ui = false;
      load-on-startup = false;
    };
    qwen3-embedding-4b = {
      hf-repo = "Qwen/Qwen3-Embedding-4B-GGUF:Q4_K_M";
      embedding = true;
      pooling = "last";
      ctx-size = 8192;
      parallel = 1;
      gpu-layers = 999;
      flash-attn = "on";
      sleep-idle-seconds = 900;
      ui = false;
      load-on-startup = false;
    };
  };
  models-preset = (pkgs.formats.ini { }).generate "llama-server-models-preset.ini" models;
  download-args =
    model:
    [
      "-hf"
      model.hf-repo
    ]
    ++ lib.optional (!(model.mmproj-auto or true)) "--no-mmproj"
    ++ lib.optional ((model.spec-type or null) == "draft-mtp") "--mtp";
  download-models = pkgs.writeShellApplication {
    name = "llama-download-models";
    text = ''
      export LLAMA_CACHE=${lib.escapeShellArg cache-directory}
      mkdir -p "$LLAMA_CACHE"

      download_one() {
        case "$1" in
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: model:
          "    ${lib.escapeShellArg name}) ${
                lib.escapeShellArgs (
                  [
                    llama
                    "download"
                  ]
                  ++ download-args model
                )
              } ;;"
        ) models
      )}
          *) echo "unknown model: $1" >&2; return 1 ;;
        esac
      }

      if [ "$#" -eq 0 ]; then
        set -- ${lib.escapeShellArgs (lib.attrNames models)}
      fi

      for model in "$@"; do
        echo "downloading $model" >&2
        download_one "$model"
      done
    '';
  };
in
{
  home = {
    activation = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      llama-server-state-directory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p ${lib.escapeShellArg state-directory}
      '';
    };
    packages = [
      pkgs.llama-cpp
      download-models
    ];
  };

  launchd.agents.llama-server = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      EnvironmentVariables = {
        LLAMA_CACHE = cache-directory;
      };
      KeepAlive = true;
      ProcessType = "Background";
      Program = llama-server;
      ProgramArguments = [
        "--host"
        "127.0.0.1"
        "--port"
        "11435"
        "--models-preset"
        "${models-preset}"
        "--models-max"
        "2"
        "--models-autoload"
      ];
      RunAtLoad = true;
      StandardErrorPath = "${state-directory}/stderr.log";
      StandardOutPath = "${state-directory}/stdout.log";
      ThrottleInterval = 30;
    };
  };
}
