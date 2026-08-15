{
  config,
  lib,
  pkgs,
  ...
}:
let
  llama-server = lib.getExe' pkgs.llama-cpp "llama-server";
  state-directory = "${config.xdg.stateHome}/llama-server";
  models-preset = (pkgs.formats.ini { }).generate "llama-server-models-preset.ini" {
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
    ];
  };

  launchd.agents.llama-server = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      EnvironmentVariables = {
        LLAMA_CACHE = "${config.xdg.cacheHome}/llama.cpp";
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
