// zellij-rail -- a tuios-style "session rail" sidebar for Zellij.
//
// One pane, three stacked sections (sessions / terminals / files) with dim
// lowercase headers, an accent bar on the focused row, nerd-font devicons and
// per-entry git status. Rendered as raw 24-bit ANSI rather than through
// zellij-tile's `Text` helper on purpose: `Text::color_range` can only address
// the four theme "emphasis" slots, which is not enough for per-filetype icon
// colors.

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::time::Duration;
use zellij_tile::prelude::*;
// The prelude re-exports the `actions` module, not `Action` itself.
use zellij_tile::prelude::actions::Action;

// Gruvbox Light Soft. Status chrome uses the darker bg2 tone below so it is
// visually distinct from the terminal's #f2e5bc canvas.
const TEXT: &str = "#3c3836";
const SUBTEXT: &str = "#504945";
const OVERLAY: &str = "#928374";
const SURFACE: &str = "#d5c4a1";
const BLUE: &str = "#076678";
const LAVENDER: &str = "#8f3f71";
const MAUVE: &str = "#8f3f71";
const RED: &str = "#9d0006";
const PEACH: &str = "#af3a03";
const YELLOW: &str = "#b57614";
const GREEN: &str = "#79740e";
const TEAL: &str = "#427b58";
const SKY: &str = "#458588";

const ACCENT_BAR: &str = "▌";

// The bottom bar's palette (zjstatus "simple" styling in zellij.nix). The hint
// line sits directly under that bar and has to read as the same component, so
// it uses these rather than the rail's own colors above.
const BAR_BG: &str = "#d5c4a1";
const BAR_DIM: &str = "#928374";
const BAR_MID: &str = "#504945";
const BAR_ACCENT: &str = "#076678";

fn mode_badge(mode: &InputMode) -> (&'static str, &'static str) {
    match mode {
        InputMode::Locked => ("LOCKED", OVERLAY),
        InputMode::Normal => ("NORMAL", BAR_MID),
        InputMode::Tmux => ("PREFIX", BLUE),
        InputMode::Pane => ("PANE", GREEN),
        InputMode::Tab => ("TAB", YELLOW),
        InputMode::Resize => ("RESIZE", PEACH),
        InputMode::Scroll => ("SCROLL", TEAL),
        InputMode::Move => ("FOCUS", MAUVE),
        _ => ("MODE", BAR_MID),
    }
}

fn rgb(hex: &str) -> (u8, u8, u8) {
    let h = hex.trim_start_matches('#');
    let p = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0);
    (p(0), p(2), p(4))
}

fn format_duration(duration: Duration) -> String {
    let seconds = duration.as_secs();
    let days = seconds / 86_400;
    let hours = (seconds % 86_400) / 3_600;
    let minutes = (seconds % 3_600) / 60;
    let seconds = seconds % 60;
    if days > 0 {
        format!("{}d {}h", days, hours)
    } else if hours > 0 {
        format!("{}h {}m", hours, minutes)
    } else if minutes > 0 {
        format!("{}m {}s", minutes, seconds)
    } else {
        format!("{}s", seconds)
    }
}

#[derive(Clone)]
struct Seg {
    text: String,
    color: &'static str,
    bg: Option<&'static str>,
    bold: bool,
}

impl Seg {
    fn new(text: impl Into<String>, color: &'static str) -> Self {
        Seg { text: text.into(), color, bg: None, bold: false }
    }
    fn bold(mut self) -> Self {
        self.bold = true;
        self
    }
    fn on(mut self, bg: &'static str) -> Self {
        self.bg = Some(bg);
        self
    }
}

fn render_line(segs: &[Seg], cols: usize) -> String {
    let mut out = String::new();
    let mut used = 0usize;
    for seg in segs {
        if used >= cols {
            break;
        }
        let room = cols - used;
        let taken: String = if seg.text.chars().count() > room {
            seg.text.chars().take(room).collect()
        } else {
            seg.text.clone()
        };
        if taken.is_empty() {
            continue;
        }
        used += taken.chars().count();
        let (r, g, b) = rgb(seg.color);
        if seg.bold {
            out.push_str("\u{1b}[1m");
        }
        if let Some(bg) = seg.bg {
            let (br, bg_, bb) = rgb(bg);
            out.push_str(&format!("\u{1b}[48;2;{};{};{}m", br, bg_, bb));
        }
        out.push_str(&format!("\u{1b}[38;2;{};{};{}m{}", r, g, b, taken));
        out.push_str("\u{1b}[0m");
    }
    out
}

// --- git ---

#[derive(Clone, Copy, PartialEq)]
enum GitState {
    Modified,
    Added,
    Deleted,
    Untracked,
}

impl GitState {
    fn sigil(&self) -> &'static str {
        match self {
            GitState::Modified => "M",
            GitState::Added => "A",
            GitState::Deleted => "D",
            GitState::Untracked => "?",
        }
    }
    fn color(&self) -> &'static str {
        match self {
            GitState::Modified => YELLOW,
            GitState::Added => GREEN,
            GitState::Deleted => RED,
            GitState::Untracked => OVERLAY,
        }
    }
    // When a directory contains several differently-changed files we keep the
    // most interesting one rather than whichever happened to be parsed last.
    fn rank(&self) -> u8 {
        match self {
            GitState::Deleted => 3,
            GitState::Modified => 2,
            GitState::Added => 1,
            GitState::Untracked => 0,
        }
    }
}

// --- icons ---

fn icon_for(name: &str, is_dir: bool) -> (&'static str, &'static str) {
    if is_dir {
        return match name {
            ".git" => ("\u{e702}", PEACH),
            ".github" => ("\u{e709}", LAVENDER),
            "node_modules" => ("\u{e718}", RED),
            "src" | "lib" => ("\u{e5fc}", BLUE),
            _ => ("\u{f07b}", BLUE),
        };
    }
    let lower = name.to_ascii_lowercase();
    match lower.as_str() {
        "readme.md" => return ("\u{f48a}", SKY),
        "flake.nix" | "flake.lock" => return ("\u{f313}", SKY),
        "dockerfile" => return ("\u{f308}", BLUE),
        "makefile" | "justfile" => return ("\u{e779}", PEACH),
        ".gitignore" | ".gitattributes" => return ("\u{e702}", PEACH),
        _ => {}
    }
    let ext = lower.rsplit_once('.').map(|(_, e)| e).unwrap_or("");
    match ext {
        "nix" => ("\u{f313}", SKY),
        "rs" => ("\u{e7a8}", PEACH),
        "py" => ("\u{e73c}", YELLOW),
        "js" | "mjs" | "cjs" => ("\u{e74e}", YELLOW),
        "ts" | "tsx" => ("\u{e628}", BLUE),
        "json" => ("\u{e60b}", YELLOW),
        "toml" | "ini" | "cfg" | "conf" => ("\u{e6b2}", PEACH),
        "yaml" | "yml" => ("\u{e6a8}", RED),
        "md" | "markdown" => ("\u{f48a}", SKY),
        "sh" | "bash" | "zsh" | "fish" => ("\u{f489}", GREEN),
        "lua" => ("\u{e620}", BLUE),
        "go" => ("\u{e627}", TEAL),
        "c" | "h" => ("\u{e61e}", BLUE),
        "cpp" | "cc" | "hpp" => ("\u{e61d}", BLUE),
        "lock" => ("\u{f023}", OVERLAY),
        "log" => ("\u{f18d}", OVERLAY),
        "txt" => ("\u{f15c}", SUBTEXT),
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" => ("\u{f1c5}", MAUVE),
        "zip" | "tar" | "gz" | "xz" | "zst" => ("\u{f410}", RED),
        _ => ("\u{f15b}", SUBTEXT),
    }
}

// --- hints ---

/// Short label for the actions worth advertising in the hint line. `None`
/// means "not interesting enough to show", which is most of them -- the point
/// is a readable line, not an exhaustive dump of the keymap.
///
/// Note these are struct variants in zellij 0.45 (`NewPane { .. }`), not the
/// tuple variants older examples show.
fn action_label(action: &Action) -> Option<String> {
    Some(match action {
        Action::SwitchToMode { input_mode } => match input_mode {
            InputMode::Normal => "normal".into(),
            InputMode::Locked => "lock".into(),
            InputMode::Pane => "pane".into(),
            InputMode::Tab => "tab".into(),
            InputMode::Resize => "resize".into(),
            // Two relabels, both because zellij's mode list is a closed enum
            // and these slots are being reused (see zellij.nix): Move is bound
            // to focus movement rather than pane movement, and Tmux is the
            // Ctrl+Space prefix's armed state, nothing to do with tmux itself.
            InputMode::Move => "focus".into(),
            InputMode::Scroll => "scroll".into(),
            InputMode::Search => "search".into(),
            InputMode::Session => "session".into(),
            InputMode::Tmux => "prefix".into(),
            InputMode::RenamePane => "rename pane".into(),
            InputMode::RenameTab => "rename tab".into(),
            _ => return None,
        },
        // A split reads better than "new pane" once the direction is known,
        // which it is for everything bound in zellij.nix.
        Action::NewPane { direction: Some(Direction::Right), .. }
        | Action::NewTiledPane { direction: Some(Direction::Right), .. } => "split right".into(),
        Action::NewPane { direction: Some(Direction::Down), .. }
        | Action::NewTiledPane { direction: Some(Direction::Down), .. } => "split down".into(),
        Action::NewPane { .. } | Action::NewTiledPane { .. } => "new pane".into(),
        Action::NewFloatingPane { command: Some(command), .. } => {
            match command.command.file_name().and_then(|name| name.to_str()) {
                Some("broot") => "broot".into(),
                Some("lazygit") => "lazygit".into(),
                Some("lzj") | Some(".lzj-wrapped") => "lzj".into(),
                _ => "float".into(),
            }
        }
        Action::NewFloatingPane { .. } => "float".into(),
        Action::NewStackedPane { .. } => "stack".into(),
        Action::NewTab { .. } => "new tab".into(),
        Action::CloseFocus => "close".into(),
        Action::CloseTab => "close tab".into(),
        Action::ToggleFocusFullscreen => "zoom".into(),
        Action::ToggleFloatingPanes => "floating".into(),
        Action::GoToNextTab => "next tab".into(),
        Action::GoToPreviousTab => "prev tab".into(),
        // Each mode's own verbs, so e.g. resize mode leads with "h resize"
        // rather than falling back to the global Alt bindings.
        Action::Resize { .. } => "resize".into(),
        Action::ScrollUp | Action::ScrollDown => "scroll".into(),
        Action::PageScrollUp | Action::PageScrollDown => "page".into(),
        Action::MoveFocus { .. } => "move".into(),
        Action::SwitchFocus | Action::FocusNextPane => "next pane".into(),
        Action::Detach => "detach".into(),
        Action::Quit => "quit".into(),
        _ => return None,
    })
}

/// Display order for the hint line. Keymap order is arbitrary, and the line is
/// usually cut off by the pane width, so the most useful entries are ranked to
/// the front rather than left to chance.
fn label_rank(label: &str) -> usize {
    const ORDER: [&str; 21] = [
        "pane", "tab", "resize", "focus", "scroll", "broot", "lazygit", "lzj", "page",
        "rail", "move", "split right", "split down", "new pane", "new tab", "zoom", "close",
        "detach", "prefix", "lock", "normal",
    ];
    ORDER.iter().position(|l| *l == label).unwrap_or(ORDER.len())
}

/// Build the hint pairs for the active mode. Keys bound to several actions are
/// labelled by the first action that has a label, and each label is shown only
/// once (several keys often map to the same thing -- arrows and hjkl both move
/// focus, say).
fn hints_for(mode_info: &ModeInfo) -> Vec<(String, String)> {
    let mut seen: Vec<String> = Vec::new();
    let mut out: Vec<(String, String)> = Vec::new();
    for (mode, bindings) in &mode_info.keybinds {
        if *mode != mode_info.mode {
            continue;
        }
        for (key, actions) in bindings {
            let key_string = key.to_string();
            // A binding that *ends* in SwitchToMode is doing something and
            // then returning (`z` toggles frames then goes to Normal); calling
            // that one "normal" is just wrong. Only a binding whose sole
            // action is a mode switch gets labelled by the mode.
            // Alt+r is deliberately a repeated right-focus action whose
            // destination is the fixed rail, so advertise its intent rather
            // than the low-level MoveFocus actions used to implement it.
            let label = if key_string == "Alt r" {
                Some("rail".into())
            } else if actions.len() == 1 {
                action_label(&actions[0])
            } else {
                actions
                    .iter()
                    .filter(|a| !matches!(a, Action::SwitchToMode { .. }))
                    .find_map(|a| action_label(a))
            };
            if let Some(label) = label {
                let key = key_string;
                // Prefer the plainest key for a given action. Several keys
                // usually reach the same place (h and Alt+Left both move
                // focus); showing the modifier-laden one is just noise, and
                // which arrives first is down to keymap order. A key with
                // modifiers stringifies as "Ctrl p" -- hence the space test.
                if let Some(existing) = out.iter_mut().find(|(_, l)| *l == label) {
                    if existing.0.contains(' ') && !key.contains(' ') {
                        existing.0 = key;
                    }
                    continue;
                }
                seen.push(label.clone());
                out.push((key, label));
            }
        }
    }
    // Plain keys first, then modifier ones, each group by usefulness. The
    // global Alt bindings exist in every mode, so without the demotion they
    // crowd out the keys that are actually specific to the mode you are in.
    out.sort_by_key(|(key, label)| (key.contains(' '), label_rank(label)));
    out
}

// --- model ---

#[derive(Clone)]
struct Entry {
    name: String,
    is_dir: bool,
    git: Option<GitState>,
}

#[derive(Clone)]
struct TerminalRow {
    title: String,
    pane_id: u32,
    tab_position: usize,
    focused: bool,
    agent_active: bool,
}

#[derive(Clone)]
struct SessionRow {
    name: String,
    is_current: bool,
    lifetime: String,
}

// What a given rendered line can be acted on as. Headers are not selectable,
// so the selection index below counts only these.
#[derive(Clone)]
enum Target {
    Session(String),
    Tab(usize),
    Terminal(u32),
    Dir(PathBuf),
    File(PathBuf),
}

#[derive(Clone)]
struct KakouneClient {
    session: String,
    client: String,
}

#[derive(Default)]
struct State {
    sessions: Vec<SessionRow>,
    current_session: Option<String>,
    terminals: Vec<TerminalRow>,
    entries: Vec<Entry>,
    cwd: PathBuf,
    git_branch: Option<String>,
    git: BTreeMap<String, GitState>,
    selected: usize,
    // Remember the cursor independently for every directory. This makes h/l
    // navigation spatially stable instead of jumping to the first row.
    directory_selections: BTreeMap<PathBuf, usize>,
    // When moving to a parent, select the child directory we just left once
    // that parent's asynchronously refreshed listing is rendered.
    pending_path_selection: Option<PathBuf>,
    targets: Vec<Target>,
    click_targets: Vec<Option<usize>>,
    show_hidden: bool,
    // Set from the `role "hints"` plugin config. The same wasm serves both the
    // rail and the one-line hint bar, so the layout can load it twice without
    // a second build.
    hints_role: bool,
    top_role: bool,
    mode_info: Option<ModeInfo>,
    git_summary: Option<String>,
    agent_panes: BTreeSet<u32>,
    // Explicitly registered by the `kz` wrapper. Pane identity is stable;
    // process events and terminal titles are not, especially during startup.
    kakoune_clients: BTreeMap<u32, KakouneClient>,
    shell_path: String,
    kak_path: String,
    zoxide_path: String,
    // Foreground processes reported by CommandChanged. Shells are omitted so
    // an idle pane keeps its normal title, while active tools are visible.
    active_commands: BTreeMap<u32, String>,
    animation_frame: usize,
    timer_ticks: usize,
    active_tab: Option<usize>,
    tabs: Vec<TabInfo>,
    top_status: String,
    pane_manifest: PaneManifest,
    // The focused terminal's cwd as of the last time we looked. Compared
    // against rather than followed blindly so that browsing the rail by hand
    // isn't immediately yanked back by the next SessionUpdate: we only re-sync
    // when the focused pane's own directory actually changes (a `cd`, or focus
    // moving to a pane that is somewhere else).
    last_focus_cwd: Option<PathBuf>,
    // Kept even while the rail or one of its floating tools owns focus. This
    // is the terminal that file/directory activations should act on.
    last_work_pane: Option<u32>,
}

register_plugin!(State);

impl State {
    fn refresh_terminals(&mut self) {
        let mut focused_pane = None;
        // CommandChanged is edge-triggered: a rail loaded after an agent has
        // started will not receive the event that launched it. PaneInfo is the
        // snapshot fallback, while agent_panes remains the live signal.
        let agent_panes = self.agent_panes.clone();
        let mut terminals = Vec::new();
        for (tab_position, panes) in &self.pane_manifest.panes {
            for p in panes
                .iter()
                .filter(|p| !p.is_plugin && p.is_selectable && !p.is_suppressed)
            {
                if p.is_focused {
                    focused_pane = Some(PaneId::Terminal(p.id));
                    if !matches!(p.title.as_str(), "broot" | "lazygit" | "lzj") {
                        self.last_work_pane = Some(p.id);
                    }
                }
                let manifest_agent = p
                    .terminal_command
                    .as_deref()
                    .map(Self::text_is_agent)
                    .unwrap_or(false)
                    || Self::text_is_agent(&p.title);
                let active_title = self.active_commands.get(&p.id).cloned().or_else(|| {
                    p.terminal_command
                        .as_deref()
                        .and_then(Self::display_command)
                });
                terminals.push(TerminalRow {
                    title: active_title.unwrap_or_else(|| p.title.clone()),
                    pane_id: p.id,
                    tab_position: *tab_position,
                    focused: p.is_focused,
                    agent_active: agent_panes.contains(&p.id) || manifest_agent,
                });
            }
        }
        self.terminals = terminals;
        // A fresh workspace deliberately starts with the rail focused, so no
        // terminal has yet produced an is_focused=true snapshot. Seed the
        // destination from the first real terminal in the active tab; once a
        // terminal is focused, the normal tracking above replaces it.
        if self.last_work_pane.is_none() {
            self.last_work_pane = self
                .terminals
                .iter()
                .find(|terminal| {
                    self.active_tab == Some(terminal.tab_position)
                        && !matches!(terminal.title.as_str(), "broot" | "lazygit" | "lzj")
                })
                .or_else(|| {
                    self.terminals.iter().find(|terminal| {
                        !matches!(terminal.title.as_str(), "broot" | "lazygit" | "lzj")
                    })
                })
                .map(|terminal| terminal.pane_id);
        }
        self.sync_to_focused_pane(focused_pane);
    }

    fn refresh_git(&self) {
        let cwd = self.cwd.to_string_lossy().to_string();
        let mut status_ctx = BTreeMap::new();
        status_ctx.insert("rail".to_owned(), "status".to_owned());
        run_command(&["git", "-C", &cwd, "status", "--porcelain"], status_ctx);

        let mut branch_ctx = BTreeMap::new();
        branch_ctx.insert("rail".to_owned(), "branch".to_owned());
        run_command(
            &["git", "-C", &cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            branch_ctx,
        );
    }

    fn refresh_sessions(&self) {
        let mut context = BTreeMap::new();
        context.insert("rail".to_owned(), "sessions".to_owned());
        run_command(
            &["zellij", "list-sessions", "--no-formatting", "--reverse"],
            context,
        );
    }

    fn parse_sessions(&mut self, stdout: &[u8]) -> bool {
        let mut sessions = Vec::new();
        for line in String::from_utf8_lossy(stdout).lines().map(str::trim) {
            let Some((name, rest)) = line.split_once(" [Created ") else { continue };
            let Some((lifetime, _)) = rest.split_once(" ago]") else { continue };
            let line_is_current = line.ends_with("(current)");
            if line_is_current {
                self.current_session = Some(name.to_owned());
            }
            sessions.push(SessionRow {
                name: name.to_owned(),
                is_current: line_is_current || self.current_session.as_deref() == Some(name),
                lifetime: lifetime.to_owned(),
            });
        }
        // A running rail necessarily belongs to at least one session. Treat
        // an empty response as a transient CLI failure instead of flashing
        // the whole session section away and back on the next poll.
        if sessions.is_empty() {
            return false;
        }
        let changed = sessions.len() != self.sessions.len()
            || sessions.iter().zip(&self.sessions).any(|(a, b)| {
                a.name != b.name || a.is_current != b.is_current || a.lifetime != b.lifetime
            });
        if changed {
            self.sessions = sessions;
        }
        changed
    }

    fn command_is_agent(command: &[String]) -> bool {
        command.iter().any(|part| Self::text_is_agent(part))
    }

    fn display_command(command: &str) -> Option<String> {
        let executable = command.split_whitespace().next()?;
        let name = std::path::Path::new(executable)
            .file_name()?
            .to_string_lossy()
            .to_string();
        if matches!(name.as_str(), "sh" | "bash" | "zsh" | "fish" | "nu") {
            None
        } else {
            Some(name)
        }
    }

    fn text_is_agent(text: &str) -> bool {
        let text = text.to_ascii_lowercase();
        ["codex", "claude", "hermes", "opencode", "gemini"]
            .iter()
            .any(|agent| text.contains(agent))
    }

    fn refresh_git_summary(&self) {
        let cwd = self.cwd.to_string_lossy().to_string();
        let mut context = BTreeMap::new();
        context.insert("rail".to_owned(), "summary".to_owned());
        run_command(
            &["git", "-C", &cwd, "status", "--porcelain=v2", "--branch"],
            context,
        );
    }

    fn parse_git_summary(&mut self, stdout: &[u8]) {
        let text = String::from_utf8_lossy(stdout);
        if text.trim().is_empty() {
            self.git_summary = None;
            return;
        }
        let mut branch = "HEAD".to_owned();
        let (mut ahead, mut behind, mut staged, mut modified, mut untracked) =
            (0usize, 0usize, 0usize, 0usize, 0usize);
        for line in text.lines() {
            if let Some(name) = line.strip_prefix("# branch.head ") {
                branch = name.to_owned();
            } else if let Some(ab) = line.strip_prefix("# branch.ab ") {
                for item in ab.split_whitespace() {
                    if let Some(value) = item.strip_prefix('+') {
                        ahead = value.parse().unwrap_or(0);
                    } else if let Some(value) = item.strip_prefix('-') {
                        behind = value.parse().unwrap_or(0);
                    }
                }
            } else if line.starts_with("? ") {
                untracked += 1;
            } else if line.starts_with("1 ") || line.starts_with("2 ") || line.starts_with("u ") {
                let xy = line.as_bytes().get(2..4).unwrap_or_default();
                if xy.first().copied().unwrap_or(b'.') != b'.' {
                    staged += 1;
                }
                if xy.get(1).copied().unwrap_or(b'.') != b'.' {
                    modified += 1;
                }
            }
        }
        let mut parts = vec![format!(" {}", branch)];
        if ahead > 0 { parts.push(format!("↑{}", ahead)); }
        if behind > 0 { parts.push(format!("↓{}", behind)); }
        if staged > 0 { parts.push(format!("+{}", staged)); }
        if modified > 0 { parts.push(format!("~{}", modified)); }
        if untracked > 0 { parts.push(format!("?{}", untracked)); }
        if staged + modified + untracked == 0 { parts.push("✓".to_owned()); }
        self.git_summary = Some(parts.join(" "));
    }

    fn parse_git_status(&mut self, stdout: &[u8]) {
        self.git.clear();
        for line in String::from_utf8_lossy(stdout).lines() {
            if line.len() < 4 {
                continue;
            }
            let code = &line[..2];
            let path = line[3..].trim_matches('"');
            // Only the first path component matters: a change deep inside a
            // directory should light up that directory's row in this listing.
            let first = path.split('/').next().unwrap_or(path);
            let state = if code.contains('?') {
                GitState::Untracked
            } else if code.contains('D') {
                GitState::Deleted
            } else if code.contains('A') {
                GitState::Added
            } else {
                GitState::Modified
            };
            self.git
                .entry(first.to_owned())
                .and_modify(|existing| {
                    if state.rank() > existing.rank() {
                        *existing = state;
                    }
                })
                .or_insert(state);
        }
        self.apply_git();
    }

    fn apply_git(&mut self) {
        for entry in self.entries.iter_mut() {
            entry.git = self.git.get(&entry.name).copied();
        }
    }

    fn update_files(&mut self, paths: Vec<(PathBuf, Option<FileMetadata>)>) {
        let mut entries: Vec<Entry> = Vec::new();
        for (path, meta) in paths {
            let name = match path.file_name() {
                Some(n) => n.to_string_lossy().to_string(),
                None => continue,
            };
            if !self.show_hidden && name.starts_with('.') && name != ".git" {
                continue;
            }
            entries.push(Entry {
                name,
                is_dir: meta.map(|m| m.is_dir).unwrap_or(false),
                git: None,
            });
        }
        // Directories first, then case-insensitive by name -- the ordering the
        // rail is read in, not the order the filesystem hands them over.
        entries.sort_by(|a, b| {
            b.is_dir
                .cmp(&a.is_dir)
                .then_with(|| a.name.to_ascii_lowercase().cmp(&b.name.to_ascii_lowercase()))
        });
        self.entries = entries;
        self.apply_git();
    }

    fn go_to(&mut self, path: PathBuf) {
        let previous_selection = self.selected;
        self.directory_selections
            .insert(self.cwd.clone(), previous_selection);
        self.cwd = path.clone();
        self.selected = self
            .directory_selections
            .get(&path)
            .copied()
            .unwrap_or(previous_selection);
        change_host_folder(path);
    }

    fn go_to_parent(&mut self) {
        let child = self.cwd.clone();
        let Some(parent) = child.parent().map(PathBuf::from) else { return };
        self.go_to(parent);
        self.pending_path_selection = Some(child);
    }

    /// Follow the focused terminal pane's working directory. Returns whether
    /// anything moved, so callers can decide whether a re-render is warranted.
    fn follow_cwd(&mut self, cwd: PathBuf) -> bool {
        if self.last_focus_cwd.as_ref() == Some(&cwd) {
            return false;
        }
        self.last_focus_cwd = Some(cwd.clone());
        if cwd == self.cwd {
            return false;
        }
        self.go_to(cwd);
        true
    }

    fn sync_to_focused_pane(&mut self, focused: Option<PaneId>) -> bool {
        let pane_id = match focused {
            Some(id) => id,
            None => return false,
        };
        match get_pane_cwd(pane_id) {
            Ok(cwd) => self.follow_cwd(cwd),
            Err(_) => false,
        }
    }

    fn shell_quote(path: &std::path::Path) -> String {
        format!("'{}'", path.to_string_lossy().replace('\'', "'\\''"))
    }

    fn command_for_path(path: &std::path::Path, is_dir: bool) -> String {
        let quoted = Self::shell_quote(path);
        if is_dir {
            // The interactive Zsh has Home Manager's zoxide integration, so
            // use its `z` function for every directory handoff. Clear only
            // after a successful jump so an error remains visible.
            return format!("z -- {} && clear", quoted);
        }
        match path.extension().and_then(|ext| ext.to_str()).map(str::to_ascii_lowercase).as_deref() {
            Some("pdf") => format!("zathura {} >/dev/null 2>&1 &", quoted),
            Some("mp4" | "mkv" | "webm" | "mov" | "avi" | "m4v" | "wmv" | "flv" |
                 "mp3" | "flac" | "ogg" | "opus" | "wav" | "m4a") => format!("mpv {}", quoted),
            Some("png" | "jpg" | "jpeg" | "gif" | "webp" | "bmp" | "tif" | "tiff" |
                 "svg" | "svgz" | "avif") => format!("xdg-open {} >/dev/null 2>&1 &", quoted),
            Some("stl" | "obj" | "ply" | "gltf" | "glb" | "3mf" | "off") =>
                format!("f3d {}", quoted),
            _ => format!("kz {}", quoted),
        }
    }

    fn work_pane_is_kakoune(&self, id: u32) -> bool {
        if self.kakoune_clients.contains_key(&id) {
            return true;
        }
        if self
            .active_commands
            .get(&id)
            .is_some_and(|name| matches!(name.as_str(), "kak" | "kz"))
        {
            return true;
        }
        self.pane_manifest.panes.values().flatten().any(|pane| {
            pane.id == id
                && (pane.title == "kakoune"
                    || pane.title.starts_with("kak · ")
                    || pane
                        .terminal_command
                        .as_deref()
                        .and_then(Self::display_command)
                        .is_some_and(|name| matches!(name.as_str(), "kak" | "kz")))
        })
    }

    fn kakoune_quote(value: &str) -> String {
        format!("'{}'", value.replace('\'', "''"))
    }

    fn send_kakoune_command(&self, pane_id: u32, command: &str, argument: &str) -> bool {
        let Some(target) = self.kakoune_clients.get(&pane_id) else { return false };
        if self.shell_path.is_empty() || self.kak_path.is_empty() {
            return false;
        }
        let remote_command = format!(
            "evaluate-commands -client {} -verbatim {} {}",
            Self::kakoune_quote(&target.client),
            command,
            Self::kakoune_quote(argument)
        );
        let mut context = BTreeMap::new();
        context.insert("rail".to_owned(), "kak-command".to_owned());
        run_command(
            &[
                &self.shell_path,
                "-c",
                "printf '%s\\n' \"$1\" | \"$2\" -p \"$3\"",
                "rail-kak-command",
                &remote_command,
                &self.kak_path,
                &target.session,
            ],
            context,
        );
        true
    }

    fn open_in_kakoune(&self, pane_id: u32, path: &std::path::Path, is_dir: bool) -> bool {
        let path = path.to_string_lossy().to_string();
        focus_terminal_pane(pane_id, true, false);
        if is_dir {
            if self.zoxide_path.is_empty() {
                return false;
            }
            let mut context = BTreeMap::new();
            context.insert("rail".to_owned(), "kak-cd".to_owned());
            context.insert("pane".to_owned(), pane_id.to_string());
            run_command(&[&self.zoxide_path, "query", "--", &path], context);
        } else {
            return self.send_kakoune_command(pane_id, "edit", &path);
        }
        true
    }

    fn open_in_work_pane(&self, path: &std::path::Path, is_dir: bool) {
        let Some(id) = self.last_work_pane else { return };
        if self.work_pane_is_kakoune(id) {
            self.open_in_kakoune(id, path, is_dir);
            return;
        }
        let command = Self::command_for_path(path, is_dir);
        write_chars_to_pane_id(&format!("{}\n", command), PaneId::Terminal(id));
        focus_terminal_pane(id, true, false);
    }

    fn refresh_top_status(&self) {
        let mut context = BTreeMap::new();
        context.insert("rail".to_owned(), "top-status".to_owned());
        run_command(
            &[
                "sh",
                "-c",
                "awk 'NR==1{load=$1} /^MemTotal:/{total=$2} /^MemAvailable:/{avail=$2} END{printf \"%.2f|%.0f%%|\",load,(total-avail)*100/total}' /proc/loadavg /proc/meminfo; date '+%a %d %b %H:%M'",
            ],
            context,
        );
    }

    fn display_tab_name(tab: &TabInfo) -> String {
        const NAMES: [&str; 16] = [
            "mist", "echo", "flux", "veil", "nova", "dusk", "tide", "loom", "halo", "wisp",
            "moss", "haze", "void", "drift", "ember", "lumen",
        ];
        let is_default = tab.name.is_empty()
            || tab
                .name
                .strip_prefix("Tab #")
                .map(|number| !number.is_empty() && number.chars().all(|c| c.is_ascii_digit()))
                .unwrap_or(false);
        if is_default {
            NAMES
                .get(tab.position)
                .map(|name| (*name).to_owned())
                .unwrap_or_else(|| format!("orb{}", tab.position + 1))
        } else {
            tab.name.clone()
        }
    }

    fn render_top(&self, cols: usize) {
        let mut segs = vec![
            Seg::new(
                format!(" {} ", self.current_session.as_deref().unwrap_or("zellij")),
                BAR_ACCENT,
            )
            .on(BAR_BG)
            .bold(),
        ];
        for tab in &self.tabs {
            segs.push(Seg::new("│ ", SURFACE).on(BAR_BG));
            segs.push(
                Seg::new(
                    format!(
                        "{} {} {} ",
                        tab.position + 1,
                        if tab.active { "●" } else { "○" },
                        Self::display_tab_name(tab)
                    ),
                    if tab.active { BAR_MID } else { BAR_DIM },
                )
                .on(BAR_BG),
            );
        }
        let right = if self.top_status.is_empty() {
            String::new()
        } else {
            let fields: Vec<&str> = self.top_status.trim().split('|').collect();
            if fields.len() == 3 {
                format!("│   {}  │   {}  │  {} ", fields[0], fields[1], fields[2])
            } else {
                self.top_status.trim().to_owned()
            }
        };
        let used: usize = segs.iter().map(|seg| seg.text.chars().count()).sum();
        let padding = cols.saturating_sub(used + right.chars().count());
        segs.push(Seg::new(" ".repeat(padding), BAR_DIM).on(BAR_BG));
        segs.push(Seg::new(right, BAR_MID).on(BAR_BG));
        print!("{}", render_line(&segs, cols));
    }

    /// The one-line hint bar: `key label` pairs for the current mode, read from
    /// the live keybindings rather than hardcoded, so it stays honest if the
    /// keymap changes.
    fn render_hints(&self, cols: usize) {
        let mode_info = match &self.mode_info {
            Some(m) => m,
            None => return,
        };
        let (mode_label, mode_color) = mode_badge(&mode_info.mode);
        let mut segs = vec![
            Seg::new(format!(" {:^6} ", mode_label), BAR_BG).on(mode_color).bold(),
            Seg::new(" ", BAR_DIM).on(BAR_BG),
        ];
        let git_text = self.git_summary.as_deref().unwrap_or("");
        let git_width = git_text.chars().count();

        let mut first = true;
        for (key, label) in hints_for(mode_info) {
            // Stop cleanly at the edge instead of letting render_line chop a
            // pair in half.
            let width: usize = segs.iter().map(|s| s.text.chars().count()).sum();
            let needed = key.chars().count() + label.chars().count() + 4;
            if width + needed + git_width + usize::from(git_width > 0) > cols {
                break;
            }
            if !first {
                segs.push(Seg::new(" · ", SURFACE).on(BAR_BG));
            }
            first = false;
            segs.push(Seg::new(key, BAR_MID).on(BAR_BG).bold());
            segs.push(Seg::new(format!(" {}", label), BAR_DIM).on(BAR_BG));
        }
        if git_width > 0 {
            let width: usize = segs.iter().map(|s| s.text.chars().count()).sum();
            let padding = cols.saturating_sub(width + git_width + 1);
            segs.push(Seg::new(" ".repeat(padding), BAR_DIM).on(BAR_BG));
            segs.push(Seg::new(format!("{} ", git_text), BAR_ACCENT).on(BAR_BG).bold());
        }
        // print!, not println!: a trailing newline in a one-row pane scrolls
        // the line straight out of the viewport (confirmed via
        // `zellij subscribe -f json`, which showed viewport [""] with the text
        // sitting in scrollback).
        //
        // The trailing "erase to end of line" with the bar background still
        // set is what carries the bar's color across the unused width, so the
        // hint line and the bar above it read as one block rather than a
        // strip floating on the terminal background.
        let (r, g, b) = rgb(BAR_BG);
        print!(
            "\u{1b}[48;2;{};{};{}m{}\u{1b}[48;2;{};{};{}m\u{1b}[K\u{1b}[0m",
            r,
            g,
            b,
            render_line(&segs, cols),
            r,
            g,
            b
        );
    }

    fn activate(&mut self) {
        let target = match self.targets.get(self.selected) {
            Some(t) => t.clone(),
            None => return,
        };
        match target {
            Target::Session(name) => switch_session(Some(&name)),
            Target::Tab(position) => go_to_tab((position + 1) as u32),
            Target::Terminal(id) => focus_terminal_pane(id, true, false),
            Target::Dir(path) => self.open_in_work_pane(&path, true),
            Target::File(path) => self.open_in_work_pane(&path, false),
        }
    }

    /// Descend through the file listing without changing or focusing the work
    /// pane. Opening the selected path is deliberately reserved for Enter.
    fn descend(&mut self) {
        let path = match self.targets.get(self.selected) {
            Some(Target::Dir(path)) => path.clone(),
            _ => return,
        };
        self.go_to(path);
    }

}

impl ZellijPlugin for State {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        self.shell_path = configuration.get("shell_path").cloned().unwrap_or_default();
        self.kak_path = configuration.get("kak_path").cloned().unwrap_or_default();
        self.zoxide_path = configuration.get("zoxide_path").cloned().unwrap_or_default();
        self.show_hidden = configuration
            .get("show_hidden")
            .map(|v| v == "true")
            .unwrap_or(true);
        self.hints_role = configuration.get("role").map(|v| v == "hints").unwrap_or(false);
        self.top_role = configuration.get("role").map(|v| v == "top").unwrap_or(false);
        if self.top_role {
            request_permission(&[
                PermissionType::ReadApplicationState,
                PermissionType::ChangeApplicationState,
                PermissionType::RunCommands,
                PermissionType::OpenFiles,
                PermissionType::OpenTerminalsOrPlugins,
                PermissionType::FullHdAccess,
            ]);
            subscribe(&[
                EventType::SessionUpdate,
                EventType::TabUpdate,
                EventType::Timer,
                EventType::RunCommandResult,
                EventType::PermissionRequestResult,
            ]);
            self.refresh_top_status();
            set_timeout(1.0);
            set_selectable(false);
            return;
        }
        if self.hints_role {
            // The hint bar only needs the mode, and must never take focus or
            // react to keys -- it is chrome, not a pane. The permission list
            // below is deliberately the *same* for both roles even though this
            // one only needs ReadApplicationState: grants are keyed by plugin
            // path, and both roles are the same wasm, so asking for a differing
            // subset here just risks re-prompting over an already-granted set.
            request_permission(&[
                PermissionType::ReadApplicationState,
                PermissionType::ChangeApplicationState,
                PermissionType::RunCommands,
                PermissionType::OpenFiles,
                PermissionType::OpenTerminalsOrPlugins,
                PermissionType::FullHdAccess,
            ]);
            subscribe(&[
                EventType::ModeUpdate,
                EventType::CwdChanged,
                EventType::Timer,
                EventType::RunCommandResult,
                EventType::PermissionRequestResult,
            ]);
            self.cwd = get_plugin_ids().initial_cwd;
            self.refresh_git_summary();
            set_timeout(2.0);
            set_selectable(false);
            return;
        }
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::RunCommands,
            PermissionType::OpenFiles,
            PermissionType::OpenTerminalsOrPlugins,
            PermissionType::WriteToStdin,
            PermissionType::ReadCliPipes,
            // Required by change_host_folder/scan_host_folder -- without it
            // zellij refuses both ("permission 'FullHdAccess' denied - Command
            // 'ChangeHostFolder' denied"), which leaves the file section stuck
            // on the directory the plugin started in.
            PermissionType::FullHdAccess,
        ]);
        subscribe(&[
            EventType::SessionUpdate,
            EventType::TabUpdate,
            EventType::PaneUpdate,
            EventType::CommandChanged,
            EventType::PaneClosed,
            EventType::Key,
            EventType::Mouse,
            EventType::Timer,
            EventType::FileSystemUpdate,
            EventType::FileSystemCreate,
            EventType::FileSystemDelete,
            EventType::HostFolderChanged,
            EventType::CwdChanged,
            EventType::RunCommandResult,
            EventType::PermissionRequestResult,
        ]);
        self.cwd = get_plugin_ids().initial_cwd;
        scan_host_folder(&"/host");
        self.refresh_git();
        self.refresh_sessions();
        set_timeout(0.25);
    }

    fn update(&mut self, event: Event) -> bool {
        if self.top_role {
            return match event {
                Event::TabUpdate(tabs) => {
                    self.tabs = tabs;
                    true
                }
                Event::SessionUpdate(sessions, _) => {
                    self.current_session = sessions
                        .iter()
                        .find(|session| session.is_current_session)
                        .map(|session| session.name.clone());
                    true
                }
                Event::Timer(_) => {
                    self.refresh_top_status();
                    set_timeout(1.0);
                    false
                }
                Event::RunCommandResult(_, stdout, _, context)
                    if context.get("rail").map(String::as_str) == Some("top-status") =>
                {
                    self.top_status = String::from_utf8_lossy(&stdout).trim().to_owned();
                    true
                }
                Event::PermissionRequestResult(_) => {
                    self.refresh_top_status();
                    false
                }
                _ => false,
            };
        }
        // The hint bar handles its own (small) event set and must not fall
        // through to the rail's handlers below -- sharing
        // PermissionRequestResult with them is what had this instance running
        // the rail's `git status` on load.
        if self.hints_role {
            return match event {
                Event::ModeUpdate(mode_info) => {
                    self.mode_info = Some(mode_info);
                    true
                }
                Event::CwdChanged(_, cwd, focused_client_ids) => {
                    if focused_client_ids.is_empty() {
                        return false;
                    }
                    self.cwd = cwd;
                    self.refresh_git_summary();
                    true
                }
                Event::Timer(_) => {
                    self.refresh_git_summary();
                    set_timeout(2.0);
                    false
                }
                Event::RunCommandResult(_, stdout, _, context)
                    if context.get("rail").map(String::as_str) == Some("summary") =>
                {
                    self.parse_git_summary(&stdout);
                    true
                }
                _ => false,
            };
        }
        match event {
            Event::PermissionRequestResult(_) => {
                scan_host_folder(&"/host");
                self.refresh_git();
                true
            }
            Event::Timer(_) => {
                self.timer_ticks = self.timer_ticks.wrapping_add(1);
                self.animation_frame = self.animation_frame.wrapping_add(1);
                // SessionUpdate is not consistently emitted for changes made
                // by other Zellij servers, so reconcile against the CLI every
                // second. Git is heavier and stays on a five-second cadence.
                if self.timer_ticks % 4 == 0 {
                    self.refresh_sessions();
                }
                if self.timer_ticks % 20 == 0 {
                    self.refresh_git();
                }
                set_timeout(0.25);
                // Render from the rows, not only the event cache: rows can
                // discover an already-running agent from PaneInfo.
                self.terminals.iter().any(|terminal| terminal.agent_active)
            }
            Event::HostFolderChanged(new_folder) => {
                self.cwd = new_folder;
                scan_host_folder(&"/host");
                self.refresh_git();
                true
            }
            Event::FileSystemUpdate(paths)
            | Event::FileSystemCreate(paths)
            | Event::FileSystemDelete(paths) => {
                self.update_files(paths);
                true
            }
            Event::RunCommandResult(exit_code, stdout, _, context) => {
                match context.get("rail").map(|s| s.as_str()) {
                    Some("status") => self.parse_git_status(&stdout),
                    Some("branch") => {
                        let branch = String::from_utf8_lossy(&stdout).trim().to_owned();
                        self.git_branch = if branch.is_empty() || branch == "HEAD" {
                            None
                        } else {
                            Some(branch)
                        };
                    }
                    Some("sessions") => {
                        return exit_code == Some(0) && self.parse_sessions(&stdout);
                    }
                    Some("kak-cd") => {
                        let Some(pane_id) = context
                            .get("pane")
                            .and_then(|value| value.parse::<u32>().ok())
                        else {
                            return false;
                        };
                        if exit_code == Some(0) {
                            let path = String::from_utf8_lossy(&stdout).trim().to_owned();
                            self.send_kakoune_command(pane_id, "cd", &path);
                            focus_terminal_pane(pane_id, true, false);
                        }
                        return false;
                    }
                    _ => return false,
                }
                true
            }
            Event::TabUpdate(tabs) => {
                self.active_tab = tabs.iter().find(|t| t.active).map(|t| t.position);
                self.tabs = tabs;
                true
            }
            Event::PaneUpdate(pane_manifest) => {
                self.pane_manifest = pane_manifest;
                self.refresh_terminals();
                true
            }
            Event::SessionUpdate(sessions, _) => {
                // This event is scoped to the current server and can contain
                // only the attached session. The CLI poll is authoritative
                // for membership across all servers; replacing that complete
                // list here caused it to alternate between one and all rows.
                let current_name = sessions
                    .iter()
                    .find(|session| session.is_current_session)
                    .map(|session| session.name.clone());
                if let Some(current_name) = &current_name {
                    self.current_session = Some(current_name.clone());
                }
                if self.sessions.is_empty() {
                    self.sessions = sessions
                        .iter()
                        .map(|session| SessionRow {
                            name: session.name.clone(),
                            is_current: session.is_current_session,
                            lifetime: format_duration(session.creation_time),
                        })
                        .collect();
                } else if let Some(current_name) = current_name.as_deref() {
                    for session in &mut self.sessions {
                        session.is_current = session.name == current_name;
                    }
                }
                // Session snapshots can lag PaneUpdate title changes. Use
                // this event for session identity/tab position only and leave
                // terminal rows to the live PaneUpdate stream so fast title
                // animations are not replaced by stale data.
                if let Some(current) = sessions.iter().find(|s| s.is_current_session) {
                    let active_tab = current.tabs.iter().find(|t| t.active).map(|t| t.position);
                    self.active_tab = active_tab;
                    self.refresh_terminals();
                }
                true
            }
            Event::CommandChanged(PaneId::Terminal(id), command, is_foreground, _) => {
                if is_foreground {
                    if let Some(name) = command.first().and_then(|part| Self::display_command(part)) {
                        self.active_commands.insert(id, name);
                    } else {
                        self.active_commands.remove(&id);
                        self.kakoune_clients.remove(&id);
                    }
                } else {
                    self.active_commands.remove(&id);
                }
                if is_foreground && Self::command_is_agent(&command) {
                    self.agent_panes.insert(id);
                } else {
                    self.agent_panes.remove(&id);
                }
                self.refresh_terminals();
                true
            }
            Event::PaneClosed(PaneId::Terminal(id)) => {
                self.agent_panes.remove(&id);
                self.kakoune_clients.remove(&id);
                true
            }
            Event::CwdChanged(_, cwd, focused_client_ids) => {
                // Only the pane someone is actually looking at should drag the
                // rail around -- a background pane running a script that cds
                // should not.
                if focused_client_ids.is_empty() {
                    return false;
                }
                self.follow_cwd(cwd)
            }
            Event::Key(key) => {
                match key.bare_key {
                    BareKey::Up | BareKey::Char('k') => {
                        self.selected = self.selected.saturating_sub(1)
                    }
                    BareKey::Down | BareKey::Char('j') => {
                        if self.selected + 1 < self.targets.len() {
                            self.selected += 1;
                        }
                    }
                    BareKey::Enter => self.activate(),
                    BareKey::Right | BareKey::Char('l') => self.descend(),
                    BareKey::Left | BareKey::Char('h') | BareKey::Backspace => {
                        self.go_to_parent()
                    }
                    BareKey::Char('.') => {
                        self.show_hidden = !self.show_hidden;
                        scan_host_folder(&"/host");
                    }
                    // Esc deliberately does nothing. It used to call
                    // hide_self(), which made the whole rail vanish with no
                    // obvious way to get it back.
                    _ => return false,
                }
                true
            }
            Event::Mouse(Mouse::ScrollUp(_)) => {
                self.selected = self.selected.saturating_sub(1);
                true
            }
            Event::Mouse(Mouse::ScrollDown(_)) => {
                if self.selected + 1 < self.targets.len() {
                    self.selected += 1;
                }
                true
            }
            Event::Mouse(Mouse::LeftClick(row, _)) => {
                if row >= 0 {
                    if let Some(Some(target_index)) = self.click_targets.get(row as usize) {
                        self.selected = *target_index;
                        self.activate();
                    }
                }
                true
            }
            _ => false,
        }
    }

    fn pipe(&mut self, message: PipeMessage) -> bool {
        if message.name == "rail-kak-pane" {
            if let Some(payload) = message.payload {
                let mut fields = payload.splitn(3, '\t');
                if let (Some(id), Some(session), Some(client)) =
                    (fields.next(), fields.next(), fields.next())
                {
                    if let Ok(id) = id.parse::<u32>() {
                        self.kakoune_clients.insert(
                            id,
                            KakouneClient {
                                session: session.to_owned(),
                                client: client.to_owned(),
                            },
                        );
                    }
                }
            }
            return false;
        }
        if message.name != "rail-open" {
            return false;
        }
        let Some(payload) = message.payload else { return false };
        if let Some(path) = payload.strip_prefix("dir:") {
            self.open_in_work_pane(std::path::Path::new(path), true);
        } else if let Some(path) = payload.strip_prefix("file:") {
            self.open_in_work_pane(std::path::Path::new(path), false);
        }
        false
    }

    fn render(&mut self, rows: usize, cols: usize) {
        if self.top_role {
            self.render_top(cols);
            return;
        }
        if self.hints_role {
            self.render_hints(cols);
            return;
        }
        let mut lines: Vec<Vec<Seg>> = Vec::new();
        let mut targets: Vec<Target> = Vec::new();
        // Rebuilt every frame so the click handler above and the selection
        // index always agree with what is actually on screen.
        let mut selectable_rows: Vec<usize> = Vec::new();

        let push_header = |lines: &mut Vec<Vec<Seg>>, label: &str, trailing: Option<String>| {
            let mut segs = vec![Seg::new(format!("{} ", label), SUBTEXT).bold()];
            if let Some(t) = trailing {
                segs.push(Seg::new(t, OVERLAY));
            }
            lines.push(segs);
        };

        push_header(&mut lines, "sessions", None);
        for session in &self.sessions {
            let is_selected = targets.len() == self.selected;
            selectable_rows.push(lines.len());
            let bar = if is_selected { ACCENT_BAR } else { " " };
            let name_color = if session.is_current { GREEN } else { TEXT };
            let reserved = 4 + session.lifetime.chars().count();
            let max_name = cols.saturating_sub(reserved);
            let display_name = if session.name.chars().count() > max_name {
                let keep = max_name.saturating_sub(1);
                format!("…{}", session.name.chars().skip(session.name.chars().count() - keep).collect::<String>())
            } else {
                session.name.clone()
            };
            let padding = cols.saturating_sub(
                3 + display_name.chars().count() + session.lifetime.chars().count(),
            );
            let mut segs = vec![
                Seg::new(bar, MAUVE),
                Seg::new(if session.is_current { "● " } else { "  " }, OVERLAY),
            ];
            let name = Seg::new(display_name, name_color);
            segs.push(if session.is_current { name.bold() } else { name });
            segs.push(Seg::new(" ".repeat(padding), OVERLAY));
            segs.push(Seg::new(session.lifetime.clone(), OVERLAY));
            lines.push(segs);
            targets.push(Target::Session(session.name.clone()));
        }

        push_header(&mut lines, "terminals", None);
        for (tab_index, tab) in self.tabs.iter().enumerate() {
            let is_last_tab = tab_index + 1 == self.tabs.len();
            let is_selected = targets.len() == self.selected;
            selectable_rows.push(lines.len());
            let bar = if is_selected { ACCENT_BAR } else { " " };
            lines.push(vec![
                Seg::new(bar, MAUVE),
                Seg::new(if is_last_tab { "└─ " } else { "├─ " }, SURFACE),
                Seg::new(if tab.active { "● " } else { "○ " }, OVERLAY),
                Seg::new(
                    Self::display_tab_name(tab),
                    if tab.active { LAVENDER } else { SUBTEXT },
                )
                .bold(),
            ]);
            targets.push(Target::Tab(tab.position));

            let tab_terminals: Vec<&TerminalRow> = self
                .terminals
                .iter()
                .filter(|terminal| terminal.tab_position == tab.position)
                .collect();
            for (terminal_index, terminal) in tab_terminals.iter().enumerate() {
                let is_last_terminal = terminal_index + 1 == tab_terminals.len();
                let is_selected = targets.len() == self.selected;
                selectable_rows.push(lines.len());
                let bar = if is_selected { ACCENT_BAR } else { " " };
                let activity = if terminal.agent_active {
                    const FRAMES: [&str; 8] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧"];
                    format!("{} ", FRAMES[self.animation_frame % FRAMES.len()])
                } else {
                    "  ".to_owned()
                };
                lines.push(vec![
                    Seg::new(bar, MAUVE),
                    Seg::new(if is_last_tab { "   " } else { "│  " }, SURFACE),
                    Seg::new(
                        if is_last_terminal { "└─ " } else { "├─ " },
                        SURFACE,
                    ),
                    Seg::new(
                        activity,
                        if terminal.agent_active { TEAL } else { OVERLAY },
                    ),
                    Seg::new(
                        terminal.title.clone(),
                        if terminal.focused { LAVENDER } else { SUBTEXT },
                    ),
                ]);
                targets.push(Target::Terminal(terminal.pane_id));
            }
        }

        let cwd_label = {
            let full = self.cwd.to_string_lossy().to_string();
            let max = cols.saturating_sub(8);
            if full.chars().count() > max {
                format!("…{}", full.chars().skip(full.chars().count() - max).collect::<String>())
            } else {
                full
            }
        };
        push_header(&mut lines, "files", Some(cwd_label));
        if let Some(branch) = &self.git_branch {
            lines.push(vec![
                Seg::new(" ", MAUVE),
                Seg::new("  \u{e725} ", PEACH),
                Seg::new(branch.clone(), PEACH),
            ]);
        }

        let pending_path_selection = self.pending_path_selection.clone();
        let mut pending_path_matched = false;
        for (entry_index, entry) in self.entries.iter().enumerate() {
            let path = self.cwd.join(&entry.name);
            if pending_path_selection.as_ref() == Some(&path) {
                self.selected = targets.len();
                pending_path_matched = true;
            }
            let is_selected = targets.len() == self.selected;
            selectable_rows.push(lines.len());
            let bar = if is_selected { ACCENT_BAR } else { " " };
            let (icon, icon_color) = icon_for(&entry.name, entry.is_dir);
            let name = if entry.is_dir {
                format!("{}/", entry.name)
            } else {
                entry.name.clone()
            };
            let name_color = match entry.git {
                Some(state) => state.color(),
                None if entry.is_dir => TEXT,
                None => SUBTEXT,
            };
            let mut segs = vec![
                Seg::new(bar, MAUVE),
                Seg::new(
                    if entry_index + 1 == self.entries.len() { "└─ " } else { "├─ " },
                    SURFACE,
                ),
                Seg::new(format!("{} ", icon), icon_color),
                Seg::new(name, name_color),
            ];
            if let Some(state) = entry.git {
                segs.push(Seg::new(format!(" {}", state.sigil()), state.color()));
            }
            lines.push(segs);
            targets.push(if entry.is_dir {
                Target::Dir(path)
            } else {
                Target::File(path)
            });
        }
        if pending_path_matched {
            self.pending_path_selection = None;
        }

        // Keep the selection inside the list after a directory change shrank it.
        if self.selected >= targets.len() {
            self.selected = targets.len().saturating_sub(1);
        }
        self.targets = targets;

        // Scroll so the selected row stays on screen once the listing is taller
        // than the pane.
        let selected_line = selectable_rows.get(self.selected).copied().unwrap_or(0);
        let offset = if lines.len() > rows && selected_line >= rows {
            selected_line + 1 - rows
        } else {
            0
        };

        // Mouse rows are viewport-relative while selection indexes contain
        // only actionable rows. Preserve the exact visible row -> target map,
        // including headers and scrolling, for the next click event.
        self.click_targets = (offset..(offset + rows).min(lines.len()))
            .map(|line_index| {
                selectable_rows
                    .iter()
                    .position(|selectable_line| *selectable_line == line_index)
            })
            .collect();

        // Newlines between lines only, never after the last -- a trailing one
        // scrolls the top line out of the viewport (see render_hints).
        for (i, line) in lines.iter().skip(offset).take(rows).enumerate() {
            if i > 0 {
                println!();
            }
            print!("{}", render_line(line, cols));
        }
    }
}
