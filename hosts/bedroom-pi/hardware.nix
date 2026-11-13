# Pi 4 on the stock nixpkgs path: firmware -> U-Boot -> extlinux, mainline
# kernel from cache.nixos.org (nothing compiled). Do NOT import the
# nixos-hardware raspberry-pi-4 profile or linux_rpi4: neither is cached.
{ lib, modulesPath, pkgs, ... }:
{
  imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64.nix" ];

  nixpkgs.hostPlatform = "aarch64-linux";

  boot.kernelPackages = pkgs.linuxPackages; # 6.18 LTS
  boot.supportedFilesystems.zfs = lib.mkForce false; # base.nix turns it on
  boot.loader.generic-extlinux-compatible.configurationLimit = 10;
  # The image's console=ttyAMA0 claims the UART onboard Bluetooth needs;
  # override boot.kernelParams if Bluetooth is ever wanted.

  sdImage.firmwareSize = 256; # MiB; the 30 MiB default leaves no headroom

  # SD-card wear
  fileSystems."/".options = [
    "noatime"
    "commit=60"
  ];
  zramSwap = {
    enable = true;
    memoryPercent = 50; # raise to 100 on a 2 GB Pi (comin evaluates on-device)
  };
  services.journald.extraConfig = ''
    SystemMaxUse=64M
    SyncIntervalSec=10m
  '';
  systemd.coredump.settings.Coredump.Storage = "none";

  # Hardware watchdog (bcm2835 max is 15 s); no emergency shell on a headless box.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "15s";
    RebootWatchdogSec = "30s";
  };
  systemd.enableEmergencyMode = false;

  environment.systemPackages = with pkgs; [
    alsa-utils
    iw
    usbutils
  ];
}
