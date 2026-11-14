# 3.5 mm jack (bcm2835, mainline) + Sendspin player for Music Assistant.
# Check on hardware:  aplay -l   ->  card "Headphones"
#   amixer -c Headphones sset PCM 0dB
#   speaker-test -D plughw:CARD=Headphones,DEV=0 -c 2 -t wav -l 1
{ inputs, lib, pkgs, ... }:
let
  # 9.1.0; needs Music Assistant >= 2.10.8. Switch to pkgs.sendspin on 26.11.
  sendspin = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.sendspin;
  sendspinPort = 8928;
in
{
  # Jack only: leave nixos-hardware's raspberry-pi."4".audio off (nixos-hardware#703).
  boot.kernelModules = [ "snd_bcm2835" ];
  boot.kernelParams = [ "snd_bcm2835.enable_headphones=1" ];
  hardware.alsa.enable = true; # plain ALSA, no PipeWire/Pulse

  # MA discovers the player via its _sendspin._tcp mDNS record and connects
  # to ws://<pi>:8928/sendspin. Unpaired guest access is the default.
  systemd.services.sendspin = {
    description = "Sendspin player (Music Assistant)";
    wantedBy = [ "multi-user.target" ];
    # It advertises the IP it sees at startup; start after the network is up.
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "sound.target"
    ];
    path = [ pkgs.alsa-utils ]; # amixer for hardware volume
    serviceConfig = {
      ExecStart = lib.escapeShellArgs [
        "${sendspin}/bin/sendspin"
        "daemon"
        "--name"
        "Bedroom"
        "--settings-dir"
        "/var/lib/sendspin"
        "--audio-device"
        # PortAudio name, matched by prefix. sendspin 9.1.0 only accepts raw ALSA
        # names (plughw:CARD=...) if `aplay -L` lists them, which failed here.
        "bcm2835 Headphones"
        "--port"
        (toString sendspinPort)
        "--disable-mpris"
      ];
      DynamicUser = true;
      StateDirectory = "sendspin";
      SupplementaryGroups = [ "audio" ];
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
  networking.firewall.allowedTCPPorts = [ sendspinPort ];

  # sendspin advertises its IP once, at startup. When the cable is plugged in or
  # pulled (or Wi-Fi comes and goes) that address goes stale and Music Assistant
  # keeps dialling a dead IP. Restart sendspin after any end0/wlan0 state change,
  # debounced: a burst of events schedules one restart 5 s later (a still-pending
  # transient unit makes systemd-run fail, which we ignore). Also keeps restarts
  # well under systemd's start rate limit.
  services.networkd-dispatcher = {
    enable = true;
    rules.sendspin-follow-network = {
      onState = [
        "routable"
        "degraded"
        "no-carrier"
        "off"
      ];
      script = ''
        #!${pkgs.runtimeShell}
        case "$IFACE" in
          end0 | wlan0) ;;
          *) exit 0 ;;
        esac
        echo "network change on $IFACE ($OperationalState): restarting sendspin in 5 s"
        ${pkgs.systemd}/bin/systemd-run --unit=sendspin-network-restart --collect \
          --on-active=5s ${pkgs.systemd}/bin/systemctl try-restart sendspin.service || true
        exit 0
      '';
    };
  };

  # Fallback if Sendspin misbehaves (disable sendspin first; MA would merge them):
  # services.squeezelite = {
  #   enable = true;
  #   name = "Bedroom";
  #   extraArgs = "-s <MA host IP> -o sysdefault:CARD=Headphones -V PCM -C 5";
  # };
}
