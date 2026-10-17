{ self, inputs }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.navicula;
in
{
  imports = [
    (import ./zellij.nix { inherit self inputs; })
    (import ./kakoune.nix { inherit self inputs; })
    (import ./shell.nix { inherit inputs; })
  ];

  options.programs.navicula = {
    enable = lib.mkEnableOption "the Navicula terminal workspace";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.navicula;
      defaultText = lib.literalExpression "navicula.packages.\${pkgs.system}.navicula";
      description = "Navicula launcher package to install.";
    };

    zellij.enable = lib.mkEnableOption "Navicula's Zellij workspace" // {
      default = true;
    };

    kakoune.enable = lib.mkEnableOption "Navicula's Kakoune editor" // {
      default = true;
    };

    shell.enable = lib.mkEnableOption "Navicula's portable Zsh environment" // {
      default = true;
    };

    iris.enable = lib.mkEnableOption "Iris shell suggestions" // {
      default = true;
    };

    prompt.enable = lib.mkEnableOption "the Navicula Starship prompt" // {
      default = true;
    };

    kitty.enable = lib.mkEnableOption "the Navicula Kitty profile" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
