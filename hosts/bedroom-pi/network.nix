# Ethernet (DHCP) always works; Wi-Fi comes up once secrets.yaml exists and
# the Pi's age key is on the device. Keep wired as the break-glass path.
{ config, lib, pkgs, ... }:
let
  hasSecrets = builtins.pathExists ./secrets.yaml;
  firmwareLabel = config.sdImage.firmwarePartitionName;
in
{
  networking.useNetworkd = true;
  systemd.network.wait-online.anyInterface = true;

  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    # Install secrets from a systemd unit so it can be ordered after the key import below.
    useSystemdActivation = true;
  }
  // lib.optionalAttrs hasSecrets {
    defaultSopsFile = ./secrets.yaml;
    # secrets.yaml: wifi_ssid, wifi_psk. The SSID is secret too: a public SSID
    # can be geolocated (e.g. WiGLE).
    secrets.wifi_ssid = { };
    secrets.wifi_psk = { };
    # Whole network block rendered at runtime under /run/secrets; nothing
    # Wi-Fi-related ends up in the (public) store or image.
    templates."wpa-networks.conf" = {
      owner = "wpa_supplicant";
      restartUnits = [ "wpa_supplicant.service" ];
      content = ''
        country=GB
        network={
          ssid="${config.sops.placeholder.wifi_ssid}"
          psk="${config.sops.placeholder.wifi_psk}"
        }
      '';
    };
  };

  # First boot: copy sops-age-key.txt from the SD card's FIRMWARE (FAT)
  # partition to /var/lib/sops-nix/key.txt, then delete it from the card.
  # Writing a FAT file works from macOS/Windows; see README.
  systemd.services.import-sops-age-key = {
    wantedBy = [ "sysinit.target" ];
    before = [
      "sysinit.target"
      "sops-install-secrets.service"
    ];
    after = [ "local-fs.target" ];
    unitConfig = {
      DefaultDependencies = "no";
      ConditionPathExists = "!/var/lib/sops-nix/key.txt";
    };
    path = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      dev=/dev/disk/by-label/${firmwareLabel}
      for _ in $(seq 20); do [ -e "$dev" ] && break; sleep 0.5; done
      [ -e "$dev" ] || exit 0
      mnt=$(mktemp -d)
      mount -t vfat "$dev" "$mnt" || { rmdir "$mnt"; exit 0; }
      if [ -s "$mnt/sops-age-key.txt" ]; then
        install -D -m 0600 "$mnt/sops-age-key.txt" /var/lib/sops-nix/key.txt
        rm -f "$mnt/sops-age-key.txt"
        echo "imported sops age key"
      fi
      umount "$mnt"
      rmdir "$mnt"
    '';
  };

  # No declarative networks: wpa_supplicant runs with an empty imperative.conf
  # plus -I <rendered template>.
  networking.wireless = lib.mkIf hasSecrets {
    enable = true;
    extraConfigFiles = [ config.sops.templates."wpa-networks.conf".path ];
  };

  # brcmfmac power save causes drops (nvmd/nixos-raspberrypi#87).
  systemd.services.wlan-powersave-off = lib.mkIf hasSecrets {
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-subsystem-net-devices-wlan0.device" ];
    bindsTo = [ "sys-subsystem-net-devices-wlan0.device" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.iw}/bin/iw dev wlan0 set power_save off";
    };
  };
}
