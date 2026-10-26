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
                mountOptions = [ "umask=0077" ];
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
                # ストアのファイルは mtime が 1970 年なので、relatime でも読むたびに 1 日 1 回 atime が書き換わる。
                # 1 日に約 100 万件あり、NVMe の書き込みを減らすため止める。atime を使うのは tmpfiles の
                # /tmp・/var/tmp の古さの判定くらいで、読むだけのファイルが早めに消えうるのは許す。
                mountOptions = [ "noatime" ];
              };
            };
          };
        };
      };
    };
  };
}
