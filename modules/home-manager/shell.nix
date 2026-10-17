{ inputs }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.navicula;
  system = pkgs.stdenv.hostPlatform.system;
  irisPackage = inputs.iris.packages.${system}.default;
  aliases = {
    ls = "eza --icons";
    ll = "eza -l --icons --git";
    la = "eza -la --icons --git";
    lt = "eza --tree --icons";
    lt2 = "eza --tree --icons --level=2";
    lt3 = "eza --tree --icons --level=3";
    lsg = "eza -l --icons --git --git-ignore";
    g = "git";
    gst = "git status";
    glog = "git log --oneline --graph --decorate";
  };
in
lib.mkIf (cfg.enable && cfg.shell.enable) (lib.mkMerge [
  {
    programs.eza = {
      enable = true;
      enableZshIntegration = true;
    };
    programs.zoxide = {
      enable = true;
      enableZshIntegration = true;
    };
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      shellAliases = aliases;
      initContent = lib.mkAfter ''
        nd() {
          command nix develop "$@" --command zsh -l
        }
        zmv() {
          if (( $# < 2 )); then
            print -u2 'usage: zmv SOURCE... ZOXIDE_QUERY'
            return 2
          fi
          local destination
          destination=$(zoxide query -- "''${@[-1]}") || return 1
          command mv -- "''${@[1,-2]}" "$destination"
        }
        zcp() {
          if (( $# < 2 )); then
            print -u2 'usage: zcp SOURCE... ZOXIDE_QUERY'
            return 2
          fi
          local destination
          destination=$(zoxide query -- "''${@[-1]}") || return 1
          command cp -r -- "''${@[1,-2]}" "$destination"
        }
      '';
    };
  }

  (lib.mkIf cfg.kitty.enable {
    programs.kitty = {
      enable = true;
      settings = {
        shell = "${pkgs.zsh}/bin/zsh";
        font_family = "JetBrainsMono Nerd Font";
        background_opacity = "1.0";
        foreground = "#504945";
        background = "#f2e5bc";
        selection_foreground = "#3c3836";
        selection_background = "#d5c4a1";
        cursor = "#9d0006";
        cursor_text_color = "#f2e5bc";
        url_color = "#076678";
        enable_audio_bell = false;
        color0 = "#ebdbb2";
        color1 = "#cc241d";
        color2 = "#98971a";
        color3 = "#d79921";
        color4 = "#458588";
        color5 = "#b16286";
        color6 = "#689d6a";
        color7 = "#7c6f64";
        color8 = "#a89984";
        color9 = "#cc241d";
        color10 = "#98971a";
        color11 = "#d79921";
        color12 = "#458588";
        color13 = "#b16286";
        color14 = "#689d6a";
        color15 = "#504945";
        confirm_os_window_close = "0";
        cursor_trail = "3";
        cursor_trail_decay = "0.1 0.25";
        cursor_trail_start_threshold = "3 1";
        cursor_trail_color = "#9d0006";
      };
    };
  })

  (lib.mkIf cfg.iris.enable {
    home.packages = [ irisPackage ];
    programs.zsh.initContent = lib.mkBefore ''
      eval "$(${irisPackage}/bin/iris init zsh)"
    '';
    xdg.configFile = {
      "iris/config.toml".source = (pkgs.formats.toml { }).generate "iris-config.toml" {
        core = { version = 1; shell = "zsh"; mode = "last"; expand-alias = true; };
        ui = { style = "modern"; ghost-text = 1; max-height = 8; nerd-fonts = true; };
        updater = { check-on-startup = false; auto-update = 0; };
        zoxide.extend-cd = true;
      };
      "iris/theme.toml".source = (pkgs.formats.toml { }).generate "iris-theme.toml" {
        border = "#b57614"; accent = "#076678"; muted = "#a89984";
        text = "#665c54"; text_sel = "#3c3836"; key = "#8f3f71";
        match = "#79740e"; desc = "#928374"; desc_sel = "#3c3836";
        sel_bg = "#d5c4a1"; sel_text = "#3c3836"; scroll_info = "#b57614";
        ghost_text = "#a89984"; sys = "#ebdbb2"; sys_sel = "#bdae93";
        hist = "#ebdbb2"; hist_sel = "#bdae93"; alias = "#ebdbb2";
        alias_sel = "#bdae93";
      };
      "iris/specs/zoxide-file-ops.json".text = builtins.toJSON [
        { name = "zmv"; description = "Move files to a directory selected through zoxide"; generator = "file"; }
        { name = "zcp"; description = "Copy files to a directory selected through zoxide"; generator = "file"; }
      ];
    };
  })

  (lib.mkIf cfg.prompt.enable {
    programs.starship = {
      enable = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      settings = builtins.fromTOML (builtins.readFile ./starship.toml);
    };
  })
])
