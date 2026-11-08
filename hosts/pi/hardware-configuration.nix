{ pkgs, ... }:
{
  # nixos-hardware の raspberry-pi-4 は linux-rpi を前提にしており、そのカーネルは
  # cache に無く Pi 自身でビルドすることになるため、nixpkgs の aarch64 SD イメージと
  # 同じく mainline と extlinux で起動する。
  boot.kernelPackages = pkgs.linuxPackages;
  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };
  # ルートは VL805 (PCIe の先) に繋いだ USB の SSD にある。
  # mainline では xhci-pci と usb-storage は組み込みで、この 2 つはモジュール。
  boot.initrd.availableKernelModules = [
    "pcie-brcmstb"
    "uas"
  ];

  hardware.enableRedistributableFirmware = true;

  # SD イメージから書いた SSD なので、イメージが付ける固定の UUID になっている
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
    fsType = "ext4";
  };
}
