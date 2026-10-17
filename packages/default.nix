{ pkgs, inputs }:

let
  wasmPkgs = pkgs.pkgsCross.wasm32-wasip1;
  crossWasmOverride = pkg: pkg.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ wasmPkgs.lld ];
    env = (old.env or { }) // {
      RUSTFLAGS = (old.env.RUSTFLAGS or "") + " -C linker=wasm-ld";
    };
  });

  railRaw = crossWasmOverride (wasmPkgs.rustPlatform.buildRustPackage {
    pname = "zellij-rail";
    version = "0.1.0";
    src = ../zellij-rail;
    cargoLock.lockFile = ../zellij-rail/Cargo.lock;
  });

  zellij-rail = pkgs.stdenvNoCC.mkDerivation {
    pname = "zellij-rail";
    version = "0.1.0";
    src = railRaw;
    dontUnpack = true;
    buildPhase = ''
      runHook preBuild
      cp "$(find "$src" -name '*.wasm')" rail.wasm
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm444 rail.wasm "$out"
      runHook postInstall
    '';
    meta = {
      description = "Session, terminal, and file rail for Zellij";
      license = pkgs.lib.licenses.mit;
      platforms = pkgs.lib.platforms.linux;
    };
  };

  lazy-zellij = pkgs.stdenvNoCC.mkDerivation {
    pname = "lazy-zellij";
    version = "unstable-2026-06-10";
    src = inputs.lazy-zellij;
    patches = [ ../lazy-zellij-delete.patch ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -m755 bin/lzj bin/zj bin/lzj-snapshot "$out/bin/"
      sed -i '/set -euo pipefail/a INSIDE_ZELLIJ=''${ZELLIJ:-}' "$out/bin/lzj"
      sed -i 's/\[ -n "''${ZELLIJ:-}" \]/[ -n "$INSIDE_ZELLIJ" ]/' "$out/bin/lzj"
      sed -i 's|"$HOME/.local/bin/lzj-snapshot"|"''${SELF%/lzj}/lzj-snapshot"|' "$out/bin/lzj"
      patchShebangs "$out/bin"
      for command in lzj zj lzj-snapshot; do
        wrapProgram "$out/bin/$command" \
          --prefix PATH : ${pkgs.lib.makeBinPath [
            pkgs.zellij pkgs.fzf pkgs.python3 pkgs.bash pkgs.systemd
            pkgs.openssh pkgs.coreutils pkgs.findutils pkgs.gawk
            pkgs.gnugrep pkgs.gnused
          ]}
      done
      runHook postInstall
    '';
    meta = {
      description = "fzf-based session manager for Zellij";
      homepage = "https://github.com/Logos-Flux/lazy-zellij";
      license = pkgs.lib.licenses.mit;
      platforms = pkgs.lib.platforms.linux;
    };
  };

  kakoune = pkgs.kakoune-unwrapped.overrideAttrs (old: {
    pname = "navicula-kakoune";
    patches = (old.patches or [ ]) ++ [ ../kakoune-two-row-status.patch ];
  });

  typst-terminal-preview = pkgs.writeShellApplication {
    name = "typst-terminal-preview";
    runtimeInputs = [ pkgs.typst pkgs.kitty pkgs.inotify-tools pkgs.coreutils ];
    text = ''
      if [[ $# -ne 1 || ! -f "$1" ]]; then
        echo "usage: typst-terminal-preview FILE.typ" >&2
        exit 2
      fi
      source_file="$(realpath "$1")"
      preview_dir="$(mktemp -d -t typst-terminal-preview.XXXXXX)"
      watcher_pid=""
      cleanup() {
        if [[ -n "$watcher_pid" ]]; then
          kill "$watcher_pid" 2>/dev/null || true
          wait "$watcher_pid" 2>/dev/null || true
        fi
        rm -rf -- "$preview_dir"
      }
      trap cleanup EXIT INT TERM
      typst watch "$source_file" "$preview_dir/page-{p}.png" --ppi 144 &
      watcher_pid=$!
      while kill -0 "$watcher_pid" 2>/dev/null; do
        inotifywait -qq -e close_write -e moved_to -e create "$preview_dir" || break
        if [[ -s "$preview_dir/page-1.png" ]]; then
          clear
          kitten icat --clear --transfer-mode=file --align=left "$preview_dir/page-1.png"
          printf '\n%s\n' "Typst preview · $(basename "$source_file") · Ctrl+C to close"
        fi
      done
      wait "$watcher_pid"
    '';
  };

  layoutDir = pkgs.runCommand "navicula-zellij-layout" { } ''
    mkdir -p "$out/layouts"
    substitute ${../layouts/navicula.kdl} "$out/layouts/navicula.kdl" \
      --replace-fail @rail@ ${zellij-rail}
  '';

  navicula = pkgs.writeShellApplication {
    name = "navicula";
    runtimeInputs = [ pkgs.zellij pkgs.coreutils pkgs.gnugrep ];
    text = ''
      usage() {
        cat <<'EOF'
Usage: navicula [NAME]

Start or attach to a Navicula Zellij workspace. NAME creates or attaches to
navicula-NAME; without NAME a fresh memorable session name is generated.
EOF
      }

      if (( $# > 1 )); then
        printf 'navicula: expected at most one name\n' >&2
        usage >&2
        exit 2
      fi
      if (( $# == 1 )) && [[ "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        exit 0
      fi
      if (( $# == 1 )) && [[ "$1" == -* ]]; then
        printf 'navicula: unknown option: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      if [[ -n "''${ZELLIJ:-}" ]]; then
        printf 'navicula: already inside Zellij session %s\n' \
          "''${ZELLIJ_SESSION_NAME:-unknown}" >&2
        exit 1
      fi

      if (( $# == 1 )); then
        session="navicula-$1"
      else
        adjectives=(amber brisk calm clever coral cosmic crisp eager gentle lucid mellow nimble quiet radiant steady vivid)
        nouns=(badger cactus comet dolphin finch gecko heron lynx otter puffin ray seal sparrow tiger turtle)
        while true; do
          adjective="''${adjectives[RANDOM % ''${#adjectives[@]}]}"
          noun="''${nouns[RANDOM % ''${#nouns[@]}]}"
          session="navicula-$adjective-$noun"
          if ! zellij list-sessions --short --no-formatting 2>/dev/null \
            | grep --fixed-strings --line-regexp --quiet -- "$session"; then
            break
          fi
        done
      fi

      config_args=()
      user_config="''${XDG_CONFIG_HOME:-$HOME/.config}/zellij/layouts/navicula.kdl"
      if [[ ! -f "$user_config" ]]; then
        config_args=(--config-dir ${layoutDir})
      fi
      exec zellij "''${config_args[@]}" attach --create "$session" \
        options --default-layout navicula
    '';
    meta = {
      description = "Launch a named Navicula terminal workspace";
      license = pkgs.lib.licenses.mit;
      platforms = pkgs.lib.platforms.linux;
      mainProgram = "navicula";
    };
  };
in
{
  inherit navicula zellij-rail lazy-zellij kakoune typst-terminal-preview;
}
