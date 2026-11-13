# Shared by every host: SSH, nix, gitops (comin), monitoring.
{ config, lib, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  # https://github.com/Arsenikki.keys
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMDW9GdpHKXpPspO9CzvTx/6P/zELvO1Di5+GnGgd03e"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKrNGfpo8ySpfpg/cwSHwT7wkHhH+zs/C6EEfDJSTZxf"
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    min-free = 1024 * 1024 * 1024;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Pull-based gitops: evaluates main (switch) and testing-<hostname> (test,
  # bootloader untouched, so a power cycle reverts it). See README.
  services.comin = {
    enable = true;
    remotes = [
      {
        name = "origin";
        url = "https://github.com/Arsenikki/nixos-homelab.git";
      }
    ];
    exporter.openFirewall = true;
    # Only deploy commits whose tip is signed by a trusted key: the user's SSH
    # keys or the paseo agent's GPG key. GitHub web-UI merges (signed by
    # GitHub) and a stolen GitHub token alone are not enough. See README.
    sshAllowedSignersPath = "${../keys/allowed_signers}";
    gpgPublicKeyPaths = [ "${../keys/agent.asc}" ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    enabledCollectors = [ "systemd" ];
  };

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
}
