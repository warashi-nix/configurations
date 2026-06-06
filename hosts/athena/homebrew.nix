{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      extraFlags = [
        "--force-cleanup" # TODO: nix-darwin が対応したら消す
      ];
    };
    brews = [
      "mas"
    ];
    casks = [
      # keep-sorted start
      "1password"
      "alfred"
      "alt-tab"
      "amazon-photos"
      "asana"
      "cloudflare-warp"
      "cryptomator"
      "discord"
      "domzilla-caffeine"
      "elecom-mouse-util"
      "firefox"
      "font-biz-udgothic"
      "font-biz-udmincho"
      "font-biz-udpgothic"
      "font-biz-udpmincho"
      "google-chrome"
      "google-drive"
      "google-gemini"
      "karabiner-elements"
      "lasso-app"
      "orbstack"
      "orion"
      "raycast"
      "visual-studio-code"
      "zoom"
      # keep-sorted end
    ];
    masApps = {
      # keep-sorted start
      "辞書 by 物書堂" = 1380563956;
      DaisyDisk = 411643860;
      GoodLinks = 1474335294;
      LINE = 539883307;
      Pastebot = 1179623856;
      Slack = 803453959;
      Things = 904280696;
      # keep-sorted end
    };
    onActivation = {
      cleanup = "zap";
    };
  };
}
