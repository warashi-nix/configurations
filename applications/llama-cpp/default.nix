{
  config,
  lib,
  pkgs,
  ...
}:
let
  llama-server = lib.getExe' pkgs.llama-cpp "llama-server";
  state-directory = "${config.xdg.stateHome}/llama-server";
in
{
  home = {
    activation = lib.mkIf pkgs.stdenv.isDarwin {
      llama-server-state-directory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p ${lib.escapeShellArg state-directory}
      '';
    };
    packages = [
      pkgs.llama-cpp
    ];
  };

  launchd.agents.llama-server = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      EnvironmentVariables = {
        LLAMA_CACHE = "${config.xdg.cacheHome}/llama.cpp";
      };
      KeepAlive = true;
      ProcessType = "Background";
      Program = llama-server;
      ProgramArguments = [
        "-hf"
        "unsloth/gemma-4-12B-it-qat-GGUF:UD-Q4_K_XL"
        "--no-mmproj"
        "--alias"
        "gemma-4-12b-qat"
        "--host"
        "127.0.0.1"
        "--port"
        "11435"
        "--ctx-size"
        "65536"
        "--parallel"
        "1"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        "q8_0"
        "--gpu-layers"
        "999"
        "--flash-attn"
        "on"
        "--spec-type"
        "draft-mtp"
        "--spec-draft-n-max"
        "2"
        "--temp"
        "1.0"
        "--mirostat"
        "2"
        "--mirostat-ent"
        "5.0"
        "--mirostat-lr"
        "0.1"
        "--chat-template-kwargs"
        (builtins.toJSON { enable_thinking = false; })
        "--sleep-idle-seconds"
        "900"
        "--no-webui"
      ];
      RunAtLoad = true;
      StandardErrorPath = "${state-directory}/stderr.log";
      StandardOutPath = "${state-directory}/stdout.log";
      ThrottleInterval = 30;
    };
  };
}
