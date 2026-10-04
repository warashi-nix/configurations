{ lib, ... }:
{
  services.cloudflare-warp.enable = true;

  # WARP は /etc/resolv.conf を書き換えて DNS を切り替えるが、nss-resolve が先にあると
  # getaddrinfo が resolv.conf を見ないため、resolve を外して resolv.conf を唯一の入口にする。
  # nixpkgs のリスト結合では特定の要素だけを外せないので、全体を mkForce で指定する。
  system.nssDatabases.hosts = lib.mkForce [
    "mymachines"
    "files"
    "myhostname"
    "dns"
  ];
}
