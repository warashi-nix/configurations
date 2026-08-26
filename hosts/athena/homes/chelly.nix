{
  warashi.chelly = {
    uid = 501;
    gid = 1000;

    # コンテナ内の pi からホストの llama-server を叩くための名前解決。
    # llama-server は 127.0.0.1 バインドのままにして LAN へ晒さないため、
    # Lima の user-mode ネットワークがホストに割り当てる 192.168.5.2 経由で届かせる。
    # このアドレスは Lima 固有なので、共有のモジュール側ではなく athena に置く。
    runtime_options.podman.run = [
      "--add-host=athena-llama:192.168.5.2"
    ];
  };
}
