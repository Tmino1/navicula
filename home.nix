# Entrypoint for the standalone home-manager config.
# Activate with:
#   nix run home-manager/release-25.11 -- switch --flake .#$(nix eval --impure --raw --expr builtins.currentSystem)
{ pkgs, ... }:

{
  imports = [
    ./terminal.nix
    ./wezterm.nix
    ./packages.nix
  ];

  programs.home-manager.enable = true;

  home = {
    username      = "travis";
    homeDirectory = if pkgs.stdenv.isDarwin then "/Users/travis" else "/home/travis";
    stateVersion  = "25.11";
  };

  programs.git = {
    enable = true;
    settings = {
      user.name  = "Tmino1";
      user.email = "travisminor10@gmail.com";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
