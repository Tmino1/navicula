{
  description = "Navicula — an integrated terminal workspace for Zellij";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yummy-kak = {
      url = "github:Hjagu09/yummy.kak";
      flake = false;
    };
    lazy-zellij = {
      url = "github:Logos-Flux/lazy-zellij";
      flake = false;
    };
    iris = {
      url = "github:versenilvis/iris/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      naviculaPackages = import ./packages { inherit pkgs inputs; };
    in
    {
      homeManagerModules.default = import ./modules/home-manager { inherit self inputs; };

      packages.${system} = {
        inherit (naviculaPackages)
          navicula zellij-rail lazy-zellij kakoune typst-terminal-preview;
        default = naviculaPackages.navicula;
      };

      apps.${system}.default = {
        type = "app";
        program = "${naviculaPackages.navicula}/bin/navicula";
        meta.description = "Launch a Navicula terminal workspace";
      };

      checks.${system}.home-manager =
        (home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [ self.homeManagerModules.default ./tests/home.nix ];
        }).activationPackage;

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
