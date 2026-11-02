{ inputs, ... }:
{
  imports = [ inputs.rex.homeManagerModules.default ];

  # Unix socket だけで待ち受け、Mac からは SSH の LocalForward で入る。
  # allowAnonymous の TCP は、ネットワークを持つ chelly agent のコンテナからも届いてしまう。
  services.rex.enable = true;

  # ~/.ssh/config は home-manager で管理していないので、guard は必要なら `rex terminfo setup` で入れる
  programs.rex.sshGuard = false;
}
