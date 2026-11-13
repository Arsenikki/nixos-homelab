{
  description = "NixOS hosts for the kuberseni homelab";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # sendspin 9.x (MA >= 2.10.8) is only on unstable until 26.11; drop then.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    {
      nixosConfigurations.bedroom-pi = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          inputs.comin.nixosModules.comin
          ./modules/common.nix
          ./hosts/bedroom-pi
        ];
      };

      # nix build .#bedroom-pi-sd-image
      packages.aarch64-linux.bedroom-pi-sd-image =
        inputs.self.nixosConfigurations.bedroom-pi.config.system.build.sdImage;
    };
}
