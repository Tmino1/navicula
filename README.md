# Navicula

Navicula is an integrated, keyboard-driven terminal workspace built around
Zellij, Kakoune, Zsh, Kitty, and a custom session/file rail. Its visual system
is the fixed Gruvbox Light Soft palette used by the iRiS material theme.

## Public flake interface

- `homeManagerModules.default`
- `packages.x86_64-linux.navicula`
- `packages.x86_64-linux.zellij-rail`
- `packages.x86_64-linux.lazy-zellij`
- `packages.x86_64-linux.kakoune`
- `packages.x86_64-linux.typst-terminal-preview`
- `apps.x86_64-linux.default`

Run the standalone launcher with:

```sh
nix run github:Tmino1/navicula
```

## Home Manager

```nix
{
  inputs.navicula.url = "github:Tmino1/navicula";

  # In the user's Home Manager modules:
  imports = [ inputs.navicula.homeManagerModules.default ];
  programs.navicula.enable = true;
}
```

The module installs the launcher and configures the complete Zellij layout,
rail, prefix keymap, Broot previews, lazy-zellij session tooling, Kakoune,
Zsh, Iris, Starship, zoxide, and Kitty profile.

### Options

All feature switches default to `true` once `programs.navicula.enable` is set:

- `programs.navicula.zellij.enable`
- `programs.navicula.kakoune.enable`
- `programs.navicula.shell.enable`
- `programs.navicula.iris.enable`
- `programs.navicula.prompt.enable`
- `programs.navicula.kitty.enable`
- `programs.navicula.package`

### Keys

Navicula starts locked so applications receive ordinary keys. Press
`Ctrl+Space`, then:

- `p` — pane mode (`v` right split, `h` lower split, `x` close, `f` fill,
  `w` floating panes)
- `t` — tab mode
- `n` — resize mode
- `s` — scroll mode
- `f` — focus mode
- `b` — floating Broot
- `g` — floating Lazygit
- `z` — lazy-zellij session picker

`Alt+r` focuses the rail. Inside Kakoune, `,b` opens the buffer picker and
`,l` opens LSP commands.

## Development

```sh
nix flake check --no-build
nix build .#navicula
```

Kakoune uses its native syntax highlighters. The optional Helix tree-sitter
bundle is intentionally not part of the default closure because one broken
grammar should not prevent the workspace from building.
