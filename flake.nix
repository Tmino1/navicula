{
  description = "N^7 portable terminal setup (zsh + oh-my-posh + zellij + wezterm + CLI toolbelt)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, ... }:
  let
    # x86_64-darwin (Intel Mac) intentionally omitted: nixpkgs-unstable has
    # dropped support for it, so importing it fails outright on that system.
    # aarch64-darwin (Apple Silicon) covers every Mac sold since late 2020.
    systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

    mkHome = system: home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
      modules = [ ./home.nix ];
    };
  in {
    homeConfigurations = nixpkgs.lib.genAttrs systems mkHome;
  };
}
