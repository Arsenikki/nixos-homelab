# Raspberry Pi 4 in the bedroom. General-purpose; first job is the
# Music Assistant "Bedroom" player.
{ ... }:
{
  imports = [
    ./hardware.nix
    ./network.nix
    ./audio.nix
  ];

  networking.hostName = "bedroom-pi";
  system.stateVersion = "26.05";
}
