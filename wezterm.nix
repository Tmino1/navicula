# wezterm.nix — ported as-is from n7-nixconf/modules/terminal/wezterm.nix.
# NOTE: `config.colors = { ... }` below is a placeholder left in the source
# config (not a real color table) — pre-existing quirk, not introduced here.
{ ... }: {
    programs.wezterm = {
        enable = true;
        extraConfig = ''
          local wezterm = require("wezterm")
          local config = wezterm.config_builder()

          config.default_prog = { "zsh" }
          config.window_close_confirmation = 'NeverPrompt'

          -- Appearance
          config.initial_cols = 90
          config.initial_rows = 51
          config.window_background_opacity = 0.78
          config.text_background_opacity = 1.0
          config.enable_tab_bar = false
          config.window_decorations = "NONE"
          config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
          config.front_end = "OpenGL"
          config.webgpu_power_preference = "HighPerformance"
          config.enable_wayland = true
          config.colors = { ... } -- keep your existing colors

          -- Only keep non-pane keybinds
          config.keys = {
            { key = "c", mods = "CTRL|SHIFT", action = wezterm.action.CopyTo("Clipboard") },
            { key = "v", mods = "CTRL|SHIFT", action = wezterm.action.PasteFrom("Clipboard") },
          }

          wezterm.on('update-status', function(window, pane)
            local process = pane:get_foreground_process_name()
            if process and process:find('nvim') then
              window:set_config_overrides({ line_height = 0.85 })
            else
              window:set_config_overrides({ line_height = 1.0 })
            end
          end)

          return config
        '';
    };
}
