{ self, inputs }:
{ config, lib, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  naviculaPackages = self.packages.${system};
  kakouneTwoRow = naviculaPackages.kakoune;

  typstTerminalPreview = naviculaPackages.typst-terminal-preview;

  # Every Zellij session gets one Kakoune server. `-C` atomically connects to
  # it or creates it, so any number of panes can become clients without a
  # separate daemon/bootstrap step or a startup race.
  kakZellij = pkgs.writeShellApplication {
    name = "kz";
    runtimeInputs = [
      config.programs.kakoune.finalPackage
      config.programs.zellij.finalPackage
      pkgs.coreutils
    ];
    text = ''
      if [[ -z "''${ZELLIJ_SESSION_NAME:-}" ]]; then
        exec kak "$@"
      fi
      session="zellij-$(printf '%s' "$ZELLIJ_SESSION_NAME" | tr -c '[:alnum:]_-' '-')"
      client="zellij-''${ZELLIJ_PANE_ID:-standalone}"
      # Tell the rail exactly which terminal is becoming a Kakoune client.
      # Include Kakoune's exact server and client names so external file
      # pickers can use its documented client-targeted remote API.
      if [[ -n "''${ZELLIJ_PANE_ID:-}" ]]; then
        zellij pipe --name rail-kak-pane -- \
          "$ZELLIJ_PANE_ID	$session	$client" >/dev/null 2>&1 || true
      fi
      exec kak -C "$session" -e "rename-client $client" "$@"
    '';
  };

  yummyKak = pkgs.kakouneUtils.buildKakounePluginFrom2Nix {
    pname = "yummy-kak";
    version = "unstable";
    src = inputs.yummy-kak;
  };

  # Keep parsers independent: unlike the old Helix mega-bundle, one broken
  # language can no longer prevent every other grammar (or Home Manager) from
  # building. nixpkgs provides each parser and its queries as a separate
  # derivation with a stable `parser` + `queries/` layout.
  grammars = pkgs.tree-sitter-grammars;
  selectedGrammars = {
    bash = grammars.tree-sitter-bash;
    c = grammars.tree-sitter-c;
    cpp = grammars.tree-sitter-cpp;
    go = grammars.tree-sitter-go;
    javascript = grammars.tree-sitter-javascript;
    json = grammars.tree-sitter-json;
    lua = grammars.tree-sitter-lua;
    markdown = grammars.tree-sitter-markdown;
    nix = grammars.tree-sitter-nix;
    python = grammars.tree-sitter-python;
    rust = grammars.tree-sitter-rust;
    toml = grammars.tree-sitter-toml;
    tsx = grammars.tree-sitter-tsx;
    typescript = grammars.tree-sitter-typescript;
    typst = grammars.tree-sitter-typst;
    yaml = grammars.tree-sitter-yaml;
  };
  languageAliases = {
    bash = [ "sh" ];
    javascript = [ "jsx" ];
    typescript = [ "typescriptreact" ];
  };
  kakTreeSitterConfig = (pkgs.formats.toml { }).generate "kak-tree-sitter-config.toml" {
    features = {
      highlighting = true;
      text_objects = true;
    };
    grammar = lib.mapAttrs (_: grammar: {
      source.local.path = "${grammar}/parser";
    }) selectedGrammars;
    language = lib.mapAttrs (name: grammar: {
      aliases = languageAliases.${name} or [ ];
      queries.source.local.path = "${grammar}/queries";
    }) selectedGrammars;
  };

in lib.mkIf (config.programs.navicula.enable && config.programs.navicula.kakoune.enable) {
  # `kz` is a wrapper rather than the Kakoune binary itself, so give it an
  # explicit completer. `_arguments` keeps completion in "file argument"
  # context after every path, while the command-specific menu style makes an
  # ambiguous first Tab visibly useful instead of appearing to do nothing.
  programs.zsh.initContent = lib.mkAfter ''
    _kz() {
      _arguments '*:file:_files'
    }
    compdef _kz kz
    zstyle ':completion:*:*:kz:*' menu select
  '';

  # Iris owns the visible completion menu, so Zsh's `compdef` alone is only a
  # fallback for shells launched without Iris.  This custom Iris spec is what
  # supplies file and directory candidates in the normal terminal UI.
  xdg.configFile."iris/specs/kz.json".text = builtins.toJSON {
    name = "kz";
    description = "Open a file in the Zellij Kakoune session";
    generator = "file";
  };

  programs.kakoune = {
    enable = true;
    package = kakouneTwoRow;
    defaultEditor = true;
    config = {
      colorScheme = "gruvbox-rail";
      numberLines = {
        enable = true;
        highlightCursor = true;
        relative = true;
      };
      scrollOff = {
        lines = 5;
        columns = 3;
      };
      tabStop = 4;
      indentWidth = 4;
      showMatching = true;
      showWhitespace = {
        enable = true;
        lineFeed = " ";
        nonBreakingSpace = "⍽";
        space = "·";
        tab = "→";
        tabStop = " ";
      };
    };
    plugins = with pkgs.kakounePlugins; [
      active-window-kak
      kak-auto-pairs
      kak-fzf
      kakoune-buffers
      kakoune-lsp
      kakoune-rainbow
      kakoune-state-save
      yummyKak
    ];
    extraConfig = ''
      # Zellij uses the terminal title for the pane frame. Kakoune otherwise
      # mirrors its entire modeline there (buffer, position, client and shared
      # session), which is useful in a standalone terminal but far too noisy in
      # a pane. Keep the detailed Yummy modeline inside Kakoune instead.
      define-command -hidden update-kak-pane-title %{
        set-option window ui_options "terminal_title=kak · %val{bufname}"
      }
      hook global WinDisplay .* update-kak-pane-title
      try update-kak-pane-title

      # LSP is shared by every client attached to this Kakoune session.
      eval %sh{kak-lsp}
      lsp-enable

      # Keep language intelligence inside the Kakoune pane. Completion is
      # already requested by lsp-enable during InsertIdle; signatures and
      # inlay hints add context without opening another Zellij pane or GUI.
      lsp-auto-signature-help-enable
      lsp-inlay-hints-enable global
      set-option global lsp_auto_highlight_references true
      set-option global lsp_hover_anchor true
      set-option global lsp_hover_max_info_lines 12
      set-option global lsp_hover_max_diagnostic_lines 6

      # Compact, single-cell gutter marks suit the narrow editor splits and do
      # not fight the rail's tree guides. Full messages remain available via
      # hover, ,le, and the next/previous diagnostic commands.
      set-option global lsp_diagnostic_line_error_sign 'E'
      set-option global lsp_diagnostic_line_warning_sign 'W'
      set-option global lsp_diagnostic_line_info_sign 'I'
      set-option global lsp_diagnostic_line_hint_sign 'H'

      evaluate-commands %sh{
        ${pkgs.kak-tree-sitter}/bin/kak-tree-sitter \
          --config ${kakTreeSitterConfig} \
          --init "$kak_session" --kakoune --daemonize --server \
          --with-highlighting --with-text-objects
      }
      define-command -override tree-sitter-user-after-highlighter %{
        try %{ remove-highlighter "window/%opt{filetype}" }
      }

      # A full-width Yummy modeline, kept in the same Gruvbox Light Soft
      # palette as the editor and terminal. Yummy exposes the useful state as
      # modules, so this replaces the old hand-spliced lsp_modeline.
      require-module yummy_std_config
      set global yummy_fmt_left  "$mode  $bufname$modified$git "
      set global yummy_fmt_right "$lsp_error$lsp_warn$lsp_info$lsp_hint  │  $selection  │  $client_server"
      set global yummy_modified_text " [+]"
      set global yummy_git_format %{$([ -n "$kak_opt_yummy_git_branch" ] && printf %s "   $kak_opt_yummy_git_branch")}
      face global yummy_bar_space_color rgb:7c6f64,rgb:bdae93
      face global yummy_normal_mode_face rgb:bdae93,rgb:076678+b
      face global yummy_insert_mode_face rgb:282828,rgb:b57614+b
      face global yummy_bufname_face rgb:504945,rgb:bdae93+b
      face global yummy_modified_face rgb:b57614,rgb:bdae93+b
      face global yummy_git_face rgb:79740e,rgb:bdae93
      face global yummy_selection_face rgb:504945,rgb:bdae93
      face global yummy_clock_face rgb:504945,rgb:bdae93
      face global yummy_lsp_error_face rgb:9d0006,rgb:bdae93+b
      face global yummy_lsp_warn_face rgb:b57614,rgb:bdae93+b
      face global yummy_lsp_info_face rgb:076678,rgb:bdae93+b
      face global yummy_lsp_hint_face rgb:79740e,rgb:bdae93+b
      yummy-enable

      # `,l` opens kakoune-lsp's discoverable mode: h hover, a actions, R
      # rename, f format, s symbols, e diagnostics, and n/p next/previous error.
      map global normal , ':enter-user-mode user<ret>' -docstring 'User commands'
      map global user l ':enter-user-mode lsp<ret>' -docstring 'LSP'
      map global user t ':enter-user-mode tree-sitter<ret>' -docstring 'Tree-sitter'
      map global user g ':enter-user-mode git-tools<ret>' -docstring 'Git'
      # Kakoune buffers are files; Zellij tabs remain workspaces. `,b` is the
      # frequent path: a one-key picker whose labels mark the current buffer
      # with `>`, the alternate with `#`, and every modified buffer with `+`.
      # `,B` locks the operations mode so cycling and housekeeping can be
      # repeated until Escape.
      map global user b ':pick-buffers<ret>' -docstring 'Pick buffer'
      map global user B ':enter-user-mode -lock buffers<ret>' -docstring 'Buffer operations'
      unmap global buffers b
      unmap global buffers <space>
      map global buffers j ':buffer-next<ret>' -docstring 'Next buffer'
      map global buffers k ':buffer-previous<ret>' -docstring 'Previous buffer'
      map global buffers w ':write<ret>' -docstring 'Write current buffer'
      map global buffers W ':write-all<ret>' -docstring 'Write all buffers'
      map global lsp ? '<esc>:lsp-signature-help<ret>' -docstring 'signature help'
      map global goto d '<esc>:lsp-definition<ret>' -docstring 'LSP definition'
      map global goto r '<esc>:lsp-references<ret>' -docstring 'LSP references'
      map global goto y '<esc>:lsp-type-definition<ret>' -docstring 'LSP type definition'

      # Kakoune's current built-in Git module already provides gutter diffs,
      # hunk movement, blame, status and log buffers. Keep the inline actions
      # here and leave the repository-wide UI to Zellij's floating Lazygit.
      declare-user-mode git-tools
      map global git-tools d ':git show-diff<ret>' -docstring 'Show diff gutter'
      map global git-tools D ':git hide-diff<ret>' -docstring 'Hide diff gutter'
      map global git-tools r ':git update-diff<ret>' -docstring 'Refresh diff gutter'
      map global git-tools n ':git next-hunk<ret>' -docstring 'Next hunk'
      map global git-tools p ':git prev-hunk<ret>' -docstring 'Previous hunk'
      map global git-tools b ':git blame<ret>' -docstring 'Toggle blame'
      map global git-tools B ':git blame-jump<ret>' -docstring 'Open blamed commit'
      map global git-tools s ':git status<ret>' -docstring 'Repository status'
      map global git-tools l ':git log<ret>' -docstring 'Repository log'

      # File windows get Gruvbox-colored add/change/delete flags immediately;
      # saving recalculates them against HEAD. `try` keeps scratch files and
      # files outside repositories silent.
      hook global WinCreate .* %{ try %{ git show-diff } }
      hook global BufWritePost .* %{ try %{ git update-diff } }

      # New Zellij panes join this session through kz. The new client can show
      # another file while sharing buffers, registers, hooks and LSP state.
      define-command -docstring 'Kakoune client in right Zellij pane' zellij-kak-right %{
        nop %sh{
          cwd="$(dirname -- "''${kak_buffile:-$PWD/.}")"
          if [ -n "$kak_buffile" ]; then
            zellij action new-pane --direction right --cwd "$cwd" --name kakoune -- kz "$kak_buffile"
          else
            zellij action new-pane --direction right --cwd "$cwd" --name kakoune -- kz
          fi
        }
      }
      define-command -docstring 'Kakoune client in lower Zellij pane' zellij-kak-down %{
        nop %sh{
          cwd="$(dirname -- "''${kak_buffile:-$PWD/.}")"
          if [ -n "$kak_buffile" ]; then
            zellij action new-pane --direction down --cwd "$cwd" --name kakoune -- kz "$kak_buffile"
          else
            zellij action new-pane --direction down --cwd "$cwd" --name kakoune -- kz
          fi
        }
      }
      define-command -docstring 'Kakoune client in new Zellij tab' zellij-kak-tab %{
        nop %sh{
          cwd="$(dirname -- "''${kak_buffile:-$PWD/.}")"
          if [ -n "$kak_buffile" ]; then
            zellij action new-tab --cwd "$cwd" --name kakoune -- kz "$kak_buffile"
          else
            zellij action new-tab --cwd "$cwd" --name kakoune -- kz
          fi
        }
      }

      # These live inside the buffer menu, so moving a buffer into another
      # Zellij view is part of the same workflow as switching or deleting one.
      map global buffers v ':zellij-kak-right<ret>' -docstring 'Current buffer in right pane'
      map global buffers x ':zellij-kak-down<ret>' -docstring 'Current buffer in lower pane'
      map global buffers t ':zellij-kak-tab<ret>' -docstring 'Current buffer in new tab'

      define-command -docstring 'Preview Typst in a Zellij terminal pane' typst-preview-terminal %{
        evaluate-commands %sh{
          if [ "$kak_opt_filetype" != typst ] || [ -z "$kak_buffile" ]; then
            printf '%s\n' 'echo -markup %§{Error: open a saved Typst file first}§'
            exit
          fi
          cwd="$(dirname -- "$kak_buffile")"
          zellij action new-pane --direction right --cwd "$cwd" \
            --name typst-preview -- ${typstTerminalPreview}/bin/typst-terminal-preview "$kak_buffile" \
            >/dev/null
        }
      }
    '';
  };

  home.packages = [
    kakZellij
    pkgs.kak-tree-sitter
    typstTerminalPreview
    pkgs.typst
    pkgs.tinymist
    pkgs.nixd
    pkgs.rust-analyzer
    pkgs.bash-language-server
    pkgs.basedpyright
    pkgs.clang-tools
    pkgs.gopls
    pkgs.lua-language-server
    pkgs.typescript-language-server
    pkgs.vscode-langservers-extracted
    pkgs.yaml-language-server
    pkgs.taplo
    pkgs.marksman
  ];

  # Canonical Gruvbox Light Soft palette throughout. Kitty keeps bg0_soft;
  # Kakoune uses the palette's bg2 surface so editor panes remain immediately
  # distinct from idle terminals without introducing a non-Gruvbox color.
  xdg.configFile."kak/colors/gruvbox-rail.kak".text = ''
    declare-option str gruvbox_rail_bg "rgb:d5c4a1"

    face global Default            rgb:3c3836,rgb:d5c4a1
    face global PrimarySelection   rgb:fbf1c7,rgb:076678
    face global SecondarySelection rgb:fbf1c7,rgb:8f3f71
    face global PrimaryCursor      rgb:fbf1c7,rgb:9d0006+fg
    face global SecondaryCursor    rgb:fbf1c7,rgb:8f3f71+fg
    face global PrimaryCursorEol   rgb:fbf1c7,rgb:af3a03+fg
    face global SecondaryCursorEol rgb:fbf1c7,rgb:928374+fg

    face global LineNumbers        rgb:7c6f64,rgb:bdae93
    face global LineNumberCursor   rgb:fbf1c7,rgb:076678+b
    face global LineNumbersWrapped rgb:928374,rgb:bdae93
    face global BufferPadding      rgb:bdae93,rgb:d5c4a1
    face global Whitespace         rgb:bdae93+f
    face global MatchingChar       rgb:fbf1c7,rgb:79740e+b

    face global StatusLine         rgb:504945,rgb:bdae93
    face global StatusLineMode     rgb:282828,rgb:d79921+b
    face global StatusLineInfo     rgb:ebdbb2,rgb:504945
    face global StatusLineValue    rgb:fbf1c7,rgb:076678
    face global StatusCursor       rgb:3c3836,rgb:fbf1c7
    face global Prompt             rgb:b57614,rgb:3c3836+b

    face global MenuForeground     rgb:fbf1c7,rgb:076678+b
    face global MenuBackground     rgb:3c3836,rgb:d5c4a1
    face global MenuInfo           rgb:504945,rgb:d5c4a1
    face global Information        rgb:3c3836,rgb:d5c4a1
    face global Error              rgb:fbf1c7,rgb:9d0006+b
    face global DiagnosticError    rgb:9d0006,rgb:d5c4a1+b
    face global DiagnosticWarning  rgb:b57614,rgb:d5c4a1+b

    face global value         rgb:8f3f71
    face global type          rgb:b57614+b
    face global variable      rgb:076678
    face global module        rgb:79740e
    face global function      rgb:427b58
    face global string        rgb:79740e
    face global keyword       rgb:9d0006+b
    face global operator      rgb:504945
    face global attribute     rgb:af3a03
    face global comment       rgb:928374+i
    face global documentation rgb:7c6f64+i
    face global meta          rgb:427b58
    face global builtin       rgb:076678+b

    face global title  rgb:79740e+b
    face global header rgb:af3a03+b
    face global mono   rgb:665c54
    face global block  rgb:427b58
    face global link   rgb:076678+u
    face global bullet rgb:b57614
    face global list   rgb:3c3836

    # Semantic captures emitted by kak-tree-sitter's Helix queries. These use
    # the canonical Gruvbox Light colors directly instead of sourcing the
    # generated theme, whose undeclared palette options break Kakoune startup.
    face global ts_attribute                 rgb:427b58+i
    face global ts_comment                   rgb:928374+i
    face global ts_comment_block             ts_comment
    face global ts_comment_line              ts_comment
    face global ts_constant                  rgb:8f3f71
    face global ts_constant_builtin          ts_constant
    face global ts_constant_builtin_boolean  ts_constant_builtin
    face global ts_constant_character        rgb:427b58
    face global ts_constant_character_escape rgb:af3a03
    face global ts_constant_macro            ts_constant
    face global ts_constant_numeric          ts_constant
    face global ts_constant_numeric_float    ts_constant_numeric
    face global ts_constant_numeric_integer  ts_constant_numeric
    face global ts_constructor               rgb:8f3f71
    face global ts_diff_delta                rgb:b57614
    face global ts_diff_delta_moved          ts_diff_delta
    face global ts_diff_minus                rgb:9d0006
    face global ts_diff_plus                 rgb:79740e
    face global ts_function                  rgb:79740e
    face global ts_function_builtin          rgb:b57614
    face global ts_function_macro            rgb:076678
    face global ts_function_method           ts_function
    face global ts_function_special          ts_function
    face global ts_keyword                   rgb:9d0006
    face global ts_keyword_conditional       ts_keyword
    face global ts_keyword_control           ts_keyword
    face global ts_keyword_control_conditional ts_keyword_control
    face global ts_keyword_control_directive ts_keyword_control
    face global ts_keyword_control_except    ts_keyword_control
    face global ts_keyword_control_exception ts_keyword_control
    face global ts_keyword_control_import    rgb:427b58
    face global ts_keyword_control_repeat    ts_keyword_control
    face global ts_keyword_control_return    ts_keyword_control
    face global ts_keyword_directive         ts_keyword
    face global ts_keyword_function          ts_keyword
    face global ts_keyword_operator          ts_keyword
    face global ts_keyword_special           ts_keyword
    face global ts_keyword_storage           ts_keyword
    face global ts_keyword_storage_modifier  ts_keyword_storage
    face global ts_keyword_storage_modifier_mut ts_keyword_storage_modifier
    face global ts_keyword_storage_modifier_ref ts_keyword_storage_modifier
    face global ts_keyword_storage_type      ts_keyword_storage
    face global ts_label                     rgb:9d0006
    face global ts_markup_bold               +b
    face global ts_markup_heading            rgb:427b58
    face global ts_markup_heading_1          ts_markup_heading
    face global ts_markup_heading_2          ts_markup_heading
    face global ts_markup_heading_3          ts_markup_heading
    face global ts_markup_heading_4          ts_markup_heading
    face global ts_markup_heading_5          ts_markup_heading
    face global ts_markup_heading_6          ts_markup_heading
    face global ts_markup_heading_marker     ts_markup_heading
    face global ts_markup_italic             +i
    face global ts_markup_link               link
    face global ts_markup_link_label         ts_markup_link
    face global ts_markup_link_text          rgb:9d0006
    face global ts_markup_link_uri           ts_markup_link
    face global ts_markup_link_url           rgb:79740e+u
    face global ts_markup_list               list
    face global ts_markup_list_checked       ts_markup_list
    face global ts_markup_list_numbered      ts_markup_list
    face global ts_markup_list_unchecked     ts_markup_list
    face global ts_markup_list_unnumbered    ts_markup_list
    face global ts_markup_quote              block
    face global ts_markup_raw                rgb:9d0006
    face global ts_markup_raw_block          ts_markup_raw
    face global ts_markup_raw_inline         ts_markup_raw
    face global ts_markup_strikethrough      +s
    face global ts_namespace                 rgb:3c3836
    face global ts_operator                  rgb:8f3f71
    face global ts_punctuation               rgb:af3a03
    face global ts_punctuation_bracket       ts_punctuation
    face global ts_punctuation_delimiter     ts_punctuation
    face global ts_punctuation_special       ts_punctuation
    face global ts_special                   rgb:8f3f71
    face global ts_string                    rgb:79740e
    face global ts_string_escape             ts_string
    face global ts_string_regex              ts_string
    face global ts_string_regexp             rgb:af3a03
    face global ts_string_special            rgb:af3a03
    face global ts_string_special_path       ts_string_special
    face global ts_string_special_symbol     ts_string_special
    face global ts_string_symbol             ts_string
    face global ts_tag                       rgb:427b58
    face global ts_tag_error                 ts_tag
    face global ts_text_title                title
    face global ts_type                      rgb:b57614
    face global ts_type_builtin              ts_type
    face global ts_type_enum                 ts_type
    face global ts_type_enum_variant         +i
    face global ts_variable                  rgb:3c3836
    face global ts_variable_builtin          rgb:af3a03+i
    face global ts_variable_other            ts_variable
    face global ts_variable_other_member     rgb:076678
    face global ts_variable_parameter        rgb:076678+i

    face global DiagnosticHint rgb:076678,rgb:d5c4a1
    face global DiagnosticInfo rgb:427b58,rgb:d5c4a1
    face global InlayHint      rgb:928374,rgb:d5c4a1
    face global LineFlagError  rgb:9d0006,rgb:d5c4a1
    face global LineFlagHint   rgb:076678,rgb:d5c4a1
    face global LineFlagInfo   rgb:427b58,rgb:d5c4a1
    face global LineFlagWarning rgb:b57614,rgb:d5c4a1
    face global Reference      default,rgb:ebdbb2
  '';
}
