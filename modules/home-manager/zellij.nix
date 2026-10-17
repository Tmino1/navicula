# zellij.nix
#
# Replaces herdr as the daily terminal multiplexer, at your request.
#
# The sidebar is zellij-rail (./zellij-rail), written here rather than
# assembled from existing plugins. That was tried first and does not get
# there: zellij's bundled "strider" is a plain filename list with no icons
# or git, and AndrewBeniston/zellij-project-sidebar renders four ASCII
# state chars with its git-branch support commented out upstream
# ("Git branch -- disabled for now"), with no file tree at all. Neither is
# a customization away from the tuios rail.
#
# It is NOT a zellij fork: a plugin draws into the same terminal-cell grid
# tuios itself draws into, so arbitrary unicode, nerd-font devicons and
# 24-bit color are all available to it. See ./zellij-rail/src/main.rs.
#
# zjstatus (packaged in nixpkgs) still provides the top status bar.
{ self, inputs }:
{ config, lib, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  naviculaPackages = self.packages.${system};
  zellijRail = naviculaPackages.zellij-rail;
  lazyZellij = naviculaPackages.lazy-zellij;
  kakounePackage =
    if config.programs.kakoune.enable
    then config.programs.kakoune.finalPackage
    else pkgs.kakoune;

  # The three bars share one palette; spelled out once rather than repeated
  # across each format string below.
  bg = "#f2e5bc";
  fgDim = "#928374";
  fgMid = "#504945";
  fgAccent = "#076678";

  # Visible divider between the bar's groups. SURFACE rather than the dim text
  # color so it actually reads as a separator instead of blending into the
  # labels either side of it.
  sep = "#[fg=#d5c4a1,bg=${bg}] │ ";

  zjstatusPath = "file:${config.xdg.configHome}/zellij/plugins/zjstatus.wasm";
  railPath = "file:${config.xdg.configHome}/zellij/plugins/rail.wasm";

  workspacePane = ''
    pane split_direction="vertical" {
        pane
        pane size=32 name="rail" focus=true {
            plugin location="rail" {
                shell_path "${pkgs.runtimeShell}"
                kak_path "${kakounePackage}/bin/kak"
                zoxide_path "${pkgs.zoxide}/bin/zoxide"
            }
        }
    }
  '';

  tabChrome = ''
    pane size=1 borderless=true {
        plugin location="rail-top"
    }
    pane size=1 borderless=true {
        plugin location="rail-hints"
    }
  '';

  naviculaLayout = ''
    layout {
        default_tab_template {
            children
${tabChrome}
        }
        new_tab_template {
${workspacePane}
${tabChrome}
        }
        // Keep the initial workspace inside a tab so the default template
        // supplies the shared chrome on the first tab as well as later tabs.
        tab {
${workspacePane}
        }
    }
  '';

  # What a bare key does once the Ctrl+Space prefix has been pressed. Add or
  # remove an entry here and the prefix binding, the mode's own escape and the
  # hint bar all follow -- the hints are generated from the live keymap, so
  # nothing has to be updated in two places.
  #
  # `mode` is the zellij InputMode the entry actually switches to. Zellij's
  # modes are a closed enum (no user-defined ones), so "focus" is its `Move`
  # mode with the pane-moving keys rebound to focus-moving ones, relabelled in
  # the hint bar by action_label() in zellij-rail/src/main.rs.
  prefixModes = [
    { key = "p"; mode = "Pane"; }
    { key = "t"; mode = "Tab"; }
    { key = "n"; mode = "Resize"; }
    { key = "s"; mode = "Scroll"; }
    { key = "f"; mode = "Move"; } # shown as "focus"
  ];

  # Plain "" rather than '' -- a '' string strips its own common indentation,
  # which would flatten these to column 0 in the generated config.
  prefixBinds = pkgs.lib.concatMapStringsSep "\n" (
    m: "              bind \"${m.key}\" { SwitchToMode \"${m.mode}\"; }"
  ) prefixModes;

  # Every stock Ctrl-based mode key from zellij 0.45's default.kdl. All of them
  # go away: the prefix is the only way into a mode now, so leaving these bound
  # would both duplicate the scheme and clutter the hint bar.
  stockModeKeys = [ "Ctrl p" "Ctrl t" "Ctrl n" "Ctrl s" "Ctrl h" "Ctrl o" "Ctrl b" "Ctrl g" ];
  unbindArgs = pkgs.lib.concatMapStringsSep " " (key: ''"${key}"'') stockModeKeys;

  # Usage stats for the bar. Both read /proc directly rather than shelling out
  # to top/free: zjstatus re-runs these on a timer, so they have to be cheap
  # and, more importantly, non-blocking -- the usual two-sample /proc/stat CPU
  # percentage needs a sleep in the middle, which would stall the bar on every
  # refresh. Load average is the sample-free stand-in.
  cpuScript = pkgs.writeShellScript "zellij-bar-cpu" ''
    ${pkgs.gawk}/bin/awk '{ printf "%.2f", $1 }' /proc/loadavg
  '';

  memScript = pkgs.writeShellScript "zellij-bar-mem" ''
    ${pkgs.gawk}/bin/awk '
      /^MemTotal:/     { total = $2 }
      /^MemAvailable:/ { avail = $2 }
      END { if (total > 0) printf "%.0f%%", (total - avail) * 100 / total }
    ' /proc/meminfo
  '';

  # Iris wraps the interactive shell with `exec iris`. Zellij can therefore
  # discover `iris` as the pane's command when saving an exited/resurrectable
  # session, then restore the wrapper itself instead of a fresh shell. Rewrite
  # only that wrapper command; real foreground programs remain serializable.
  irisResurrectionHook = pkgs.writeShellScript "zellij-resurrect-command" ''
    command="''${RESURRECT_COMMAND:-}"
    case "$command" in
      iris|*/iris|iris\ *|*/iris\ *)
        printf '%s\n' '${pkgs.zsh}/bin/zsh'
        ;;
      *)
        printf '%s\n' "$command"
        ;;
    esac
  '';

in
lib.mkIf (config.programs.navicula.enable && config.programs.navicula.zellij.enable) {
  programs.zellij = {
    enable = true;
    # Shell integration deliberately OFF (it defaults off; spelled out because
    # it was on and actively broken): home-manager injects its auto-start at
    # mkOrder 200, i.e. the very top of .zshrc, and that block `exec zellij`s
    # the shell -- so `eval "$(iris init zsh)"` further down never ran, which
    # is why iris didn't start. Two tools that both take over the shell via
    # exec can't both be an rc hook; zellij is the one that's launched
    # deliberately (Super+H, see dank-shell.nix), matching how herdr worked
    # before it.
    enableFishIntegration = false;
    enableZshIntegration = false;

    plugins = [
      pkgs.zellijPlugins.zjstatus
      zellijRail
    ];

    # One bar, at the bottom, in dj95's "simple" example styling
    # (examples/simple.kdl upstream): mode + session + tabs on the left, CPU
    # load / memory / clock on the right.
    #
    # The separate top tab bar is gone (tabs moved in here) and so is zellij's
    # built-in status bar, which was the only source of keybinding hints -- so
    # there are no hints any more. zjstatus has no hints widget of its own;
    # the zjstatus-hints plugin that provides one was dropped earlier because
    # it hangs on an invisible permission prompt.
    #
    # The kubectx/kubens command widgets from the upstream example are dropped
    # (neither is installed here) and the timezone follows the system rather
    # than being pinned to the example's Europe/Berlin.
    layouts.navicula = naviculaLayout;

    settings = {
      # Plain `zellij` remains available without the rail workspace. The
      # The `navicula` launcher explicitly selects the integrated layout.
      default_layout = "compact";
      session_serialization = true;
      serialize_pane_viewport = true;
      post_command_discovery_hook = "${irisResurrectionHook}";

      # Start locked so the shell owns every keystroke until Ctrl+Space arms
      # the prefix (see the keybinds in extraConfig below).
      default_mode = "locked";
      theme = "gruvbox-light";

      # Pinned for the same reason kitty's `shell` is (see dank-shell.nix):
      # zellij's default_shell falls back to $SHELL, and a desktop session that
      # logged in before users.users.ad.shell changed still exports
      # SHELL=.../bin/fish. Super+H runs `kitty zellij`, i.e. kitty execs
      # zellij directly with no shell in between, so kitty's own `shell`
      # setting does not apply here -- every pane was still coming up as fish,
      # which is why .zshrc (and iris) never ran inside zellij. Verified by
      # watching a freshly-opened session spawn fish panes.
      default_shell = "${pkgs.zsh}/bin/zsh";
      # Frames around every pane, explicitly rather than by inheriting the
      # default, since this was asked for and an earlier revision turned it off.
      pane_frames = true;
      # "full" draws a complete square box around each pane; zellij's default
      # is "titles", which only draws a title line above one -- that is the
      # difference between what was on screen and the outlined look asked for.
      # (An `ui { pane_frames { rounded_corners/border_style } }` block was
      # tried here first and is a no-op: those keys are from zellij's main
      # branch, and 0.45 silently ignores unknown config nodes rather than
      # erroring, so `setup --check` still reported "Well defined".)
      pane_frame_style = "full";

      # home-manager auto-generates `load_plugins` from every entry in
      # `programs.zellij.plugins`, which is wrong for both of these: zjstatus
      # and rail are instantiated by the layout above, so background-loading
      # them too gives a second, invisible copy of each -- and the rail copy
      # would sit there running `git status` on its 5s timer forever. Nothing
      # here is a genuine background plugin any more, so the list is empty.
      load_plugins = pkgs.lib.mkForce { _children = [ ]; };

      # Written out by hand (the module would generate one entry per package)
      # to add a second alias for the *same* rail wasm carrying `role "hints"`.
      # Plugin configuration given inline in a layout's `plugin { ... }` block
      # does not reach the plugin -- verified by rendering the hint pane tall
      # and watching it draw the rail instead -- but alias configuration does.
      # This is exactly how zellij's own config distinguishes tab-bar,
      # status-bar and compact-bar, which are all one "zellij:bars" location
      # separated only by a `role` on the alias.
      plugins = pkgs.lib.mkForce {
        zjstatus._props.location = zjstatusPath;
        rail._props.location = railPath;
        rail-hints = {
          _props.location = railPath;
          role = "hints";
        };
        rail-top = {
          _props.location = railPath;
          role = "top";
        };
      };
    };

    # Literal KDL rather than `settings`: these are nested blocks with node
    # properties (`keybinds preset=... unlock=...`), which the module's
    # attrset->KDL generator expresses awkwardly at best.
    extraConfig = ''
      // A real prefix: the session starts locked (every keystroke goes to the
      // shell), Ctrl+Space arms the prefix, and then a bare key picks a mode --
      // p pane, t tab, n resize, s scroll, f focus. All the stock Ctrl+<key>
      // mode shortcuts are unbound, so the prefix is the only way in.
      //
      // The armed state is zellij's `tmux` mode. That is not about tmux being
      // installed -- it is simply zellij's built-in transient command state,
      // the only mode whose bindings return to Normal after one action, which
      // is exactly prefix behaviour. Using Normal as the armed state instead
      // would leave bare p/t/n/s/f live while typing. The hint bar relabels it
      // (see action_label in zellij-rail/src/main.rs) so "tmux" is never shown.
      //
      // Note shared_except excludes "tmux" as well as "locked": without that,
      // its Ctrl+Space binding would fight the one in the tmux block below.
      keybinds {
          locked {
              // Stock locked mode binds Ctrl+g as the way out; dropped so
              // Ctrl+Space is the only way in and the hint bar shows one key.
              unbind "Ctrl g"
              bind "Ctrl Space" { SwitchToMode "Tmux"; }
              // The rail is the fixed rightmost pane. Repeating a rightward
              // focus move crosses any intervening work splits and stops at
              // the rail without leaving locked mode.
              bind "Alt r" {
                  MoveFocus "Right"; MoveFocus "Right"; MoveFocus "Right";
                  MoveFocus "Right"; MoveFocus "Right"; MoveFocus "Right";
                  MoveFocus "Right"; MoveFocus "Right";
              }
          }
          shared_except "locked" "tmux" {
              unbind ${unbindArgs}
              bind "Ctrl Space" { SwitchToMode "Tmux"; }
              // Esc/Enter return to locked, not to normal. Stock zellij sends
              // them (and every mode action) to Normal, which is what broke
              // the loop: you went locked -> prefix -> mode -> and then landed
              // in normal, where the shell no longer owns the keyboard.
              bind "Esc" "Enter" { SwitchToMode "Locked"; }
          }
          // clear-defaults, not unbind: this mode ships a full tmux-style
          // keymap of its own ([ for scroll, % for a new pane, h/j/k/l, ...)
      // which otherwise shows up alongside the prefix keys below and wins
      // the hint line. Starting empty keeps the prefix limited to the modes
      // above plus the floating broot launcher.
          tmux clear-defaults=true {
              bind "Ctrl Space" { SwitchToMode "Locked"; }
              bind "Esc" "Enter" { SwitchToMode "Locked"; }
              bind "b" {
                  Run "${pkgs.broot}/bin/broot" {
                      floating true
                      close_on_exit true
                      name "broot"
                      x "5%"
                      y "5%"
                      width "90%"
                      height "90%"
                  }
                  SwitchToMode "Locked"
              }
              bind "g" {
                  Run "${pkgs.lazygit}/bin/lazygit" {
                      floating true
                      close_on_exit true
                      name "lazygit"
                      x "30%"
                      y "30%"
                      width "40%"
                      height "40%"
                  }
                  SwitchToMode "Locked"
              }
              bind "z" {
                  Run "${lazyZellij}/bin/lzj" {
                      floating true
                      close_on_exit true
                      name "lzj"
                      x "30%"
                      y "30%"
                      width "40%"
                      height "40%"
                  }
                  SwitchToMode "Locked"
              }
${prefixBinds}
          }
          // Every mode below is clear-defaults for the same reason the prefix
          // is: the stock bindings all end in SwitchToMode "Normal", so each
          // one silently dropped you out of the locked/prefix loop. These end
          // in "Locked" instead, closing it.
          //
          // The ones that reposition (resize, scroll, focus) deliberately stay
          // in their mode so the keys repeat; only the one-shot actions exit.

          pane clear-defaults=true {
              bind "Esc" "Enter" { SwitchToMode "Locked"; }
              bind "Ctrl Space" { SwitchToMode "Tmux"; }
              // Splits rather than a bare "new pane": v puts the new pane
              // beside this one, h stacks it below.
              bind "v" { NewPane "Right"; SwitchToMode "Locked"; }
              bind "h" { NewPane "Down"; SwitchToMode "Locked"; }
              bind "x" { CloseFocus; SwitchToMode "Locked"; }
              bind "f" { ToggleFocusFullscreen; SwitchToMode "Locked"; }
              bind "w" { ToggleFloatingPanes; SwitchToMode "Locked"; }
          }

          tab clear-defaults=true {
              // This mode clears inherited bindings, so keep its exits local.
              bind "Esc" "Enter" { SwitchToMode "Locked"; }
              bind "Ctrl Space" { SwitchToMode "Tmux"; }
              bind "n" { NewTab; SwitchToMode "Locked"; }
              bind "x" { CloseTab; SwitchToMode "Locked"; }
              bind "h" "Left"  { GoToPreviousTab; SwitchToMode "Locked"; }
              bind "l" "Right" { GoToNextTab; SwitchToMode "Locked"; }
          }

          resize clear-defaults=true {
              bind "Esc" "Enter" { SwitchToMode "Locked"; }
              bind "Ctrl Space" { SwitchToMode "Tmux"; }
              bind "h" "Left"  { Resize "Increase Left"; }
              bind "j" "Down"  { Resize "Increase Down"; }
              bind "k" "Up"    { Resize "Increase Up"; }
              bind "l" "Right" { Resize "Increase Right"; }
              bind "H" { Resize "Decrease Left"; }
              bind "J" { Resize "Decrease Down"; }
              bind "K" { Resize "Decrease Up"; }
              bind "L" { Resize "Decrease Right"; }
          }

          scroll clear-defaults=true {
              bind "Esc" "Enter" { SwitchToMode "Locked"; }
              bind "Ctrl Space" { SwitchToMode "Tmux"; }
              bind "j" "Down" { ScrollDown; }
              bind "k" "Up"   { ScrollUp; }
              bind "PageDown" { PageScrollDown; }
              bind "PageUp"   { PageScrollUp; }
          }

          // "focus" -- zellij's Move mode with MovePane rebound to MoveFocus,
          // since the mode list is a closed enum and a new one cannot be added.
          move clear-defaults=true {
              // Keep the escape bindings local to this clear-defaults mode:
              // shared bindings are not reliably retained after clearing it.
              bind "Esc" "Enter" { SwitchToMode "Locked"; }
              bind "Ctrl Space" { SwitchToMode "Tmux"; }
              bind "h" "Left"  { MoveFocus "Left"; }
              bind "j" "Down"  { MoveFocus "Down"; }
              bind "k" "Up"    { MoveFocus "Up"; }
              bind "l" "Right" { MoveFocus "Right"; }
          }
      }
    '';
  };

  # `br` remains useful outside Zellij because its shell function can apply
  # broot's selected directory to the calling Zsh. Inside Zellij,
  # Ctrl+Space b opens a large floating broot pane.
  programs.broot = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    settings = {
      # Kitty is the outer terminal and Zellij has graphics passthrough, so
      # force the high-resolution protocol instead of relying on detection
      # through the multiplexer. Ordinary supported images need no transformer.
      graphics_display = "kitty";
      kitty_graphics_display = "direct";
      kitty_graphics_transmission = "temp_file";
      preview_transformers = [
        {
          input_extensions = [ "pdf" ];
          output_extension = "png";
          mode = "image";
          command = [
            "${pkgs.mupdf}/bin/mutool" "draw" "-q" "-w" "1400"
            "-o" "{output-path}" "{input-path}" "1"
          ];
        }
        {
          input_extensions = [ "mp4" "mkv" "webm" "mov" "avi" "m4v" "wmv" "flv" ];
          output_extension = "png";
          mode = "image";
          command = [
            "${pkgs.ffmpeg}/bin/ffmpeg" "-loglevel" "error" "-ss" "1"
            "-i" "{input-path}" "-frames:v" "1" "-vf" "scale=1400:-1"
            "-y" "{output-path}"
          ];
        }
        {
          input_extensions = [ "stl" "obj" "ply" "gltf" "glb" "3mf" "off" ];
          output_extension = "png";
          mode = "image";
          command = [
            "${pkgs.f3d}/bin/f3d" "--output" "{output-path}"
            "--resolution" "1400,1000" "--no-background" "{input-path}"
          ];
        }
        {
          input_extensions = [ "svg" "svgz" ];
          output_extension = "png";
          mode = "image";
          command = [
            "${pkgs.imagemagick}/bin/magick" "{input-path}"
            "-resize" "1400x1000>" "{output-path}"
          ];
        }
      ];
      verbs = [
        # Files leave the floating picker and are opened in the most recently
        # focused work pane by the already-running rail plugin.
        {
          name = "open-in-pane";
          key = "enter";
          apply_to = "file";
          external = [ "${config.programs.zellij.finalPackage}/bin/zellij" "pipe" "--name" "rail-open" "--" "file:{file}" ];
          leave_broot = true;
        }
        # Enter remains Broot's normal descend/focus action for directories;
        # Alt+Enter sends the selected directory to the work pane, where the
        # rail dispatches it through zoxide and clears after a successful jump.
        {
          name = "cd-in-pane";
          key = "alt-enter";
          apply_to = "directory";
          external = [ "${config.programs.zellij.finalPackage}/bin/zellij" "pipe" "--name" "rail-open" "--" "dir:{file}" ];
          leave_broot = true;
        }
      ];
    };
  };

  programs.lazygit.enable = true;

  home.packages = [ naviculaPackages.navicula lazyZellij pkgs.mpv ];

  # Declarative equivalents of lazy-zellij's optional installer-managed user
  # units. The template makes its Ctrl+U/Alt+U autostart controls work, and
  # the timer keeps the fzf preview snapshots current.
  systemd.user.services = {
    lzj-snapshot = {
      Unit.Description = "Snapshot active Zellij sessions for lzj previews";
      Service = {
        Type = "oneshot";
        ExecStart = "${lazyZellij}/bin/lzj-snapshot";
        Nice = 10;
      };
    };
    "zellij@" = {
      Unit = {
        Description = "Zellij session %i";
        Documentation = "https://zellij.dev";
        After = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash -c '${config.programs.zellij.finalPackage}/bin/zellij list-sessions --short 2>/dev/null | ${pkgs.gnugrep}/bin/grep -qx \"%i\" || ${config.programs.zellij.finalPackage}/bin/zellij attach -b \"%i\"'";
        ExecStop = "${config.programs.zellij.finalPackage}/bin/zellij kill-session %i";
      };
    };
  };

  systemd.user.timers.lzj-snapshot = {
    Unit = {
      Description = "Periodic snapshots of active Zellij sessions for lzj";
      Requires = [ "lzj-snapshot.service" ];
    };
    Timer = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
