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
        "plughw:CARD=Headphones,DEV=0"
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

  # Fallback if Sendspin misbehaves (disable sendspin first; MA would merge them):
  # services.squeezelite = {
  #   enable = true;
  #   name = "Bedroom";
  #   extraArgs = "-s <MA host IP> -o sysdefault:CARD=Headphones -V PCM -C 5";
  # };
}
