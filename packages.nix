# packages.nix — curated CLI toolbelt, ported from n7-nixconf/modules/core/packages.nix.
# Dropped: GUI/CAD/gaming/hardware-specific packages (vscode, blender, freecad,
# prusa-slicer, prismlauncher, mgba/desmume, nvidia-container-toolkit,
# discord/vencord, texlive, zathura, exhibit) and Linux-only custom builds
# (ekphos, chroma — both declare `meta.platforms = lib.platforms.linux`).
{ pkgs, unstable, ... }:

let
  tiki = pkgs.buildGoModule {
    pname = "tiki";
    version = "0.5.3";
    src = pkgs.fetchFromGitHub {
      owner = "boolean-maybe";
      repo = "tiki";
      rev = "v0.1.1";
      hash = "sha256-8QhPajUv3qYEITywIU+bzx3ebBlxqNsTxU7cQY5G49o=";
    };
    vendorHash = "sha256-pbzWHkFgB5Olqa/m/Dtf3S3Dsjr0e9pfMYLPv+LkyII=";
  };

  pomo = pkgs.buildGoModule {
    pname = "pomo";
    version = "v1.2.0";
    src = pkgs.fetchFromGitHub {
      owner = "Bahaaio";
      repo  = "pomo";
      rev   = "v1.2.0";
      hash = "sha256-BssUPJ5ZlahDXqfqW+ntvsR1H4YFCaLcVLHGBGTD7HY=";
    };
    vendorHash = "sha256-kbTYq4Xc86bcmNMhInq1rwYTbGRmu2TEXT2e7bqT5YY=";
  };

  superfile = pkgs.buildGoModule {
    pname = "superfile";
    version = "v1.5.0";
    doCheck = false;
    src = pkgs.fetchFromGitHub {
      owner = "yorukot";
      repo = "superfile";
      rev = "v1.5.0";
      hash = "sha256-PEojifuiIjF3OUxDoMCyynOJUpFglTzh7lJUcq7g4e0=";
    };
    vendorHash = "sha256-5SSnrG3DvD1i7rNcpztHkUUap4Qp7MX04ofD7rA3xgM=";
  };
in
{
  home.packages = [
    tiki
    pomo
    superfile
  ] ++ (with pkgs; [
    htop
    wget
    tree
    fastfetch
    lazygit
    unzip
    ripgrep
    fd
  ]) ++ (with unstable; [
    zip
    catimg
    chafa
    ascii-image-converter
    calcurse
    glow
    gocheat
    nix-output-monitor
    just
    rmpc
    claude-code
  ]);
}
