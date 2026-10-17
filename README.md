# Navicula

Navicula is a keyboard-driven terminal workspace built around Zellij. It opens
with a persistent navigation rail beside the working pane and keeps sessions,
terminals, files, Git state, and active coding agents visible in one place.

## The rail

The custom `zellij-rail` plugin provides three connected views:

- sessions, including the current session and its age;
- tabs and terminal panes, including the foreground command and an activity
  indicator for supported coding agents;
- a file browser that follows the focused pane's working directory and shows
  repository branch and file status.

Pane, tab, command, and working-directory changes are event driven. The rail
also rescans the current directory and reconciles cross-server sessions every
500 ms, while Git state refreshes every 2 seconds. These fallback polls cover
changes made outside the current Zellij server.

Focus the rail with `Alt+r`. Navigate with the arrow keys or `j`/`k`, open the
selected row with `Enter` or `l`, move to the parent directory with `h`, and
toggle hidden files with `.`. Selecting a session connects to it, selecting a
tab or terminal focuses it, directories change the working pane's directory,
and files open in Kakoune.

## Launch

Run Navicula directly from the flake:

```sh
nix run github:Tmino1/navicula
```

The launcher starts the `navicula` Zellij layout. A plain `zellij` command is
left alone and continues to use Zellij's compact layout.

## Home Manager

```nix
{
  inputs.navicula.url = "github:Tmino1/navicula";

  # In the user's Home Manager configuration:
  imports = [ inputs.navicula.homeManagerModules.default ];
  programs.navicula.enable = true;
}
```

The module installs the launcher and configures the integrated Zellij layout,
rail, prefix keymap, Kakoune environment, shell, prompt, and Kitty profile.
Its main switches are:

```nix
programs.navicula.zellij.enable = true;
programs.navicula.kakoune.enable = true;
programs.navicula.shell.enable = true;
programs.navicula.prompt.enable = true;
programs.navicula.kitty.enable = true;
```

Each component defaults to enabled when `programs.navicula.enable` is set.
`programs.navicula.package` can replace the launcher package.

## Workspace keys

Navicula starts in locked mode so applications receive ordinary keystrokes.
Press `Ctrl+Space`, then:

- `p` — pane mode (`v` right split, `h` lower split, `x` close, `f` fill,
  `w` floating panes)
- `t` — tab mode
- `n` — resize mode
- `s` — scroll mode
- `f` — focus mode
- `b` — floating Broot
- `g` — floating Lazygit
- `z` — lazy-zellij session picker

Inside Kakoune, `,b` opens the buffer picker and `,l` opens LSP commands.

## Flake outputs

- `homeManagerModules.default`
- `packages.x86_64-linux.navicula`
- `packages.x86_64-linux.zellij-rail`
- `packages.x86_64-linux.lazy-zellij`
- `packages.x86_64-linux.kakoune`
- `packages.x86_64-linux.typst-terminal-preview`
- `apps.x86_64-linux.default`

## Development

```sh
nix flake check
nix build .#navicula
```
