{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              end = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              name = "root";
              end = "-0";
              content = {
                type = "filesystem";
                # 停電後に無人で起動させるので、mainline から外れた bcachefs ではなく ext4 にする。
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
