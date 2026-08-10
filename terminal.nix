# terminal.nix — Zsh + Oh My Posh + Zellij
# Ported from n7-nixconf/modules/terminal/terminal.nix, with the NixOS-specific
# `rebuild*` aliases swapped for generic home-manager equivalents.
{ config, pkgs, unstable, lib, ... }:

{
  # ─────────────────────────────────────────
  # Packages
  # ─────────────────────────────────────────
  home.packages = with pkgs; [
    oh-my-posh
    nerd-fonts.jetbrains-mono
    eza
    bat
  ];

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # ─────────────────────────────────────────
  # Zsh
  # ─────────────────────────────────────────
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    plugins = [
      {
        name = "zsh-autosuggestions";
        src = pkgs.zsh-autosuggestions;
        file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
      }
      {
        name = "zsh-syntax-highlighting";
        src = pkgs.zsh-syntax-highlighting;
        file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
      }
    ];

    envExtra = ''
      export ZELLIJ_AUTO_ATTACH="false"
      export ZELLIJ_AUTO_EXIT="true"
      export EDITOR="nvim"
    '';

    initExtra = ''
      eval "$(oh-my-posh init zsh --config ~/.config/oh-my-posh/theme.json)"

      alias hm-switch='home-manager switch --flake ~/n7-terminal#$(nix eval --impure --raw --expr builtins.currentSystem)'
      alias hm-update='nix flake update --flake ~/n7-terminal && hm-switch'
      alias ls='eza --icons'
      alias ll='eza -l --icons --git'
      alias la='eza -la --icons --git'
      alias lt='eza --tree --icons'
      alias lt2='eza --tree --icons --level=2'
      alias lt3='eza --tree --icons --level=3'
      alias lsg='eza -l --icons --git --git-ignore'
      alias g='git'
      alias gst='git status'
      alias glog='git log --oneline --graph --decorate'

      zmv() {
        local dest="''${@[-1]}"
        local resolved
        resolved=$(zoxide query -- "$dest") || return 1
        mv "''${@[1,-2]}" "$resolved"
      }

      zcp() {
        local dest="''${@[-1]}"
        local resolved
        resolved=$(zoxide query -- "$dest") || return 1
        cp -r "''${@[1,-2]}" "$resolved"
      }

      if [[ -z "$ZELLIJ" ]]; then
        if [[ "$ZELLIJ_AUTO_ATTACH" == "true" ]]; then
          zellij attach -c
        else
          zellij
        fi
        if [[ "$ZELLIJ_AUTO_EXIT" == "true" ]]; then
          exit
        fi
      fi
    '';
  };

  # ─────────────────────────────────────────
  # Oh My Posh — theme file
  # ─────────────────────────────────────────
  xdg.configFile."oh-my-posh/theme.json".source = ./posh-theme.json;

  # ─────────────────────────────────────────
  # Zellij
  # ─────────────────────────────────────────

  programs.zellij = {
    enable = true;
    package = unstable.zellij;
    settings = {
      default_shell = "zsh";
      default_mode = "locked";
      default_layout = "compact";
      mouse_mode = true;
      scroll_buffer_size = 1000;
      copy_on_select = false;
      pane_frames = true;
      session_serialization = true;
      theme = "ashen-ember";
    };

    extraConfig = ''
      show_startup_tips false;
      keybinds clear-defaults=true {
        locked {
          bind "Ctrl Space" { SwitchToMode "normal"; }

          bind "Ctrl o" {
            LaunchOrFocusPlugin "zellij:session-manager" {
              floating true; move_to_focused_tab true;
            };
          }

          // --- Navigation (ARROW KEYS ONLY) ---
          bind "Ctrl Left"  { MoveFocus "left"; }
          bind "Ctrl Down"  { MoveFocus "down"; }
          bind "Ctrl Up"    { MoveFocus "up"; }
          bind "Ctrl Right" { MoveFocus "right"; }

          // --- Plugin navigation (nvim integration) ---
          bind "Ctrl Shift Left" {
            MessagePlugin "file:${config.home.homeDirectory}/.config/zellij/plugins/vim-zellij-navigator.wasm" {
              name "move_focus_or_tab"; payload "left"; move_mod "ctrl";
            };
          }
          bind "Ctrl Shift Down" {
            MessagePlugin "file:${config.home.homeDirectory}/.config/zellij/plugins/vim-zellij-navigator.wasm" {
              name "move_focus"; payload "down"; move_mod "ctrl";
            };
          }
          bind "Ctrl Shift Up" {
            MessagePlugin "file:${config.home.homeDirectory}/.config/zellij/plugins/vim-zellij-navigator.wasm" {
              name "move_focus"; payload "up"; move_mod "ctrl";
            };
          }
          bind "Ctrl Shift Right" {
            MessagePlugin "file:${config.home.homeDirectory}/.config/zellij/plugins/vim-zellij-navigator.wasm" {
              name "move_focus_or_tab"; payload "right"; move_mod "ctrl";
            };
          }

          // --- Move pane (Alt arrows) ---
          bind "Alt Left"  { MovePane "left"; }
          bind "Alt Right" { MovePane "right"; }
          bind "Alt Up"    { MovePane "up"; }
          bind "Alt Down"  { MovePane "down"; }
        }

        normal {
          bind "Ctrl Space" { SwitchToMode "locked"; }
          bind "Esc"        { SwitchToMode "locked"; }

          bind "t" { NewTab; SwitchToMode "locked"; }
          bind "v" { NewPane "right"; SwitchToMode "resize"; }
          bind "h" { NewPane "down"; SwitchToMode "resize"; }
          bind "s" { NewPane "stacked"; SwitchToMode "locked"; }

          bind "x" { CloseFocus; SwitchToMode "locked"; }
          bind "f" { ToggleFocusFullscreen; SwitchToMode "locked"; }
          bind "w" { ToggleFloatingPanes; SwitchToMode "locked"; }
          bind "z" { TogglePaneFrames; SwitchToMode "locked"; }

          bind "o" { SwitchToMode "session"; }
          bind "/" { SwitchToMode "scroll"; }

          bind "Right" { GoToNextTab; }
          bind "Left"  { GoToPreviousTab; }

          bind "r" { SwitchToMode "resize"; }
          bind "T" { SwitchToMode "renametab"; TabNameInput 0; }

          bind "Alt Left"  { MovePane "left";  SwitchToMode "locked"; }
          bind "Alt Right" { MovePane "right"; SwitchToMode "locked"; }
          bind "Alt Up"    { MovePane "up";    SwitchToMode "locked"; }
          bind "Alt Down"  { MovePane "down";  SwitchToMode "locked"; }

          bind "1" { GoToTab 1; SwitchToMode "locked"; }
          bind "2" { GoToTab 2; SwitchToMode "locked"; }
          bind "3" { GoToTab 3; SwitchToMode "locked"; }
          bind "4" { GoToTab 4; SwitchToMode "locked"; }
          bind "5" { GoToTab 5; SwitchToMode "locked"; }

          bind "g" {
            Run "zsh" "-c" "lazygit"{
              floating true
              close_on_exit true
              x "10%"
              y "10%"
              width "80%"
              height "80%"
            }
            SwitchToMode "locked";
          }

         }

        scroll {
          bind "Esc" "q" { SwitchToMode "locked"; }

          bind "Down" { ScrollDown; }
          bind "Up"   { ScrollUp; }

          bind "PageDown" { HalfPageScrollDown; }
          bind "PageUp"   { HalfPageScrollUp; }

          bind "End" { ScrollToBottom; SwitchToMode "locked"; }


          bind "y" { Copy; SwitchToMode "locked"; }

          bind "/" { SwitchToMode "entersearch"; SearchInput 0; }
        }

        entersearch {
          bind "Enter" { SwitchToMode "search"; }
          bind "Esc"   { SwitchToMode "scroll"; }
        }

        search {
          bind "Esc" "q" { SwitchToMode "locked"; }
          bind "n"       { Search "down"; }
          bind "N"       { Search "up"; }
        }

        session {
          bind "Esc" { SwitchToMode "locked"; }
          bind "d"   { Detach; }

          bind "w" {
            LaunchOrFocusPlugin "zellij:session-manager" {
              floating true; move_to_focused_tab true;
            };
            SwitchToMode "locked";
          }
        }

        renametab {
          bind "Enter" "Esc" { SwitchToMode "locked"; }
        }

        resize {
          bind "Esc" "r" { SwitchToMode "locked"; }
          bind "Left"    { Resize "Increase Left"; }
          bind "Right"   { Resize "Increase Right"; }
          bind "Up"      { Resize "Increase Up"; }
          bind "Down"    { Resize "Increase Down"; }
          bind "h"       { Resize "Increase Left"; }
          bind "l"       { Resize "Increase Right"; }
          bind "k"       { Resize "Increase Up"; }
          bind "j"       { Resize "Increase Down"; }
          bind "H"       { Resize "Decrease Left"; }
          bind "L"       { Resize "Decrease Right"; }
          bind "K"       { Resize "Decrease Up"; }
          bind "J"       { Resize "Decrease Down"; }
        }
      }
      themes {
          ashen-ember {
                fg "#a89060"
                bg "#0f0e0a"
                black "#1c1a10"
                red "#b04820"
                green "#386830"
                yellow "#c8a820"
                blue "#607828"
                magenta "#985820"
                cyan "#1a9878"
                white "#a89060"
                orange "#c07018"
          }
      }

    '';
  };

  # Fetch the wasm navigator plugin declaratively
  home.file.".config/zellij/plugins/vim-zellij-navigator.wasm" = {
    source = pkgs.fetchurl {
      url  = "https://github.com/hiasr/vim-zellij-navigator/releases/download/0.3.0/vim-zellij-navigator.wasm";
      hash = "sha256-d+Wi9i98GmmMryV0ST1ddVh+D9h3z7o0xIyvcxwkxY0=";
    };
  };
}
