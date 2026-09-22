{
  warashi.chelly = {
    uid = 501;
    gid = 1000;
    settings.container_cmd = "podman";
    # Podman machine の共有範囲を境界にし、chelly 自体を専用構成にする。
    dedicated = true;
  };
}
