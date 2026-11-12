#!/bin/sh
# install.sh: install the broll-finder skill into one or more coding agents.
#
# Usage:
#   ./install.sh                        # menu; Enter (or no terminal) = every detected agent
#   ./install.sh --agent claude         # one agent
#   ./install.sh --agent claude,cursor  # several agents, comma-separated
#   ./install.sh --agent all            # every agent detected on this machine
#   ./install.sh --dest DIR             # a custom parent skills directory
#   ./install.sh --project              # ./.claude/skills in the current directory
#
# Options:
#   --force       Replace an existing install
#   --uninstall   Remove the skill from the chosen agents
#   --dry-run     Show what would happen without changing anything
#   --ref REF     Download from a branch, tag or commit (default: main)
#   --list        List supported agents and whether each one is detected
#   -h, --help    Show this help
#
# Remote install (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/axel0806/broll-finder-SKILL/main/install.sh | sh
#
# POSIX sh: works in bash, dash, zsh, ash, macOS and Git Bash on Windows.
# From Windows PowerShell, use install.ps1 instead.

set -eu

SKILL_NAME="broll-finder"
REPO="axel0806/broll-finder-SKILL"
REF="main"
REF_EXPLICIT=0
AGENTS=""
DEST=""
FORCE=0
UNINSTALL=0
DRY_RUN=0

if [ -t 1 ]; then
    G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' B='\033[1m' N='\033[0m'
else
    G='' Y='' R='' B='' N=''
fi
ok()   { printf "${G}  ok${N}     %s\n" "$1"; }
warn() { printf "${Y}  warn${N}   %s\n" "$1"; }
err()  { printf "${R}error:${N} %s\n" "$1" >&2; }
run()  { if [ "$DRY_RUN" -eq 1 ]; then printf "  [dry-run] %s\n" "$*"; else "$@"; fi; }

usage() { sed -n '2,24p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' || echo "See https://github.com/$REPO"; }

# Supported agents: id|display name|detection dir|skills dir
agent_table() {
    cat <<EOF
claude|Claude Code|$HOME/.claude|$HOME/.claude/skills
codex|Codex CLI|$HOME/.codex|$HOME/.codex/skills
gemini|Gemini CLI|$HOME/.gemini|$HOME/.gemini/skills
copilot|GitHub Copilot CLI|$HOME/.copilot|$HOME/.copilot/skills
cursor|Cursor|$HOME/.cursor|$HOME/.cursor/skills
opencode|OpenCode|$HOME/.config/opencode|$HOME/.config/opencode/skills
goose|Goose|$HOME/.config/goose|$HOME/.config/goose/skills
agents|Generic (~/.agents)|$HOME/.agents|$HOME/.agents/skills
EOF
}
agent_ids() { agent_table | cut -d'|' -f1 | tr '\n' ' '; }
agent_field() { agent_table | awk -F'|' -v id="$1" -v f="$2" '$1 == id { print $f }'; }

list_agents() {
    agent_table | while IFS='|' read -r id name detect _dir; do
        if [ -d "$detect" ]; then s="${G}detected${N}"; else s="not found"; fi
        printf "  %-9s %-20s %b\n" "$id" "$name" "$s"
    done
}

# ---- parse arguments --------------------------------------------------------
need_val() { [ "$#" -ge 2 ] && [ -n "$2" ] || { err "$1 requires a value"; exit 2; }; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --agent|--to) need_val "$@"; AGENTS="$2"; shift 2 ;;
        --dest)       need_val "$@"; DEST="$2"; shift 2 ;;
        --project)    DEST="./.claude/skills"; shift ;;
        --ref)        need_val "$@"; REF="$2"; REF_EXPLICIT=1; shift 2 ;;
        --force)      FORCE=1; shift ;;
        --uninstall)  UNINSTALL=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        --list)       list_agents; exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        *)            err "unknown option: $1"; usage >&2; exit 2 ;;
    esac
done

case "$DEST" in
    \~)   DEST=$HOME ;;
    \~/*) DEST="$HOME/${DEST#\~/}" ;;
esac

can_prompt() { [ -r /dev/tty ] && { [ -t 0 ] || [ -t 1 ]; } && (: </dev/tty) 2>/dev/null; }

# ---- WSL check --------------------------------------------------------------
# Inside WSL, $HOME is the Linux home, so agents installed on Windows would not
# see the skill. This is easy to hit by accident: 'bash' in PowerShell is WSL.
if [ -z "$DEST" ] && { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; }; then
    win_user=""
    command -v wslvar >/dev/null 2>&1 && win_user=$(wslvar USERNAME 2>/dev/null </dev/null | tr -d '\r')
    [ -n "$win_user" ] || win_user="<you>"
    warn "running inside WSL: this installs into the Linux home ($HOME), not Windows."
    printf "         Agents running on Windows will NOT see it. For them, run in PowerShell:\n"
    printf "           & ([scriptblock]::Create((irm https://raw.githubusercontent.com/%s/main/install.ps1)))\n" "$REPO"
    printf "         or install from here with --dest /mnt/c/Users/%s/.claude/skills\n" "$win_user"
    if can_prompt && [ "$DRY_RUN" -eq 0 ]; then
        printf "Continue installing into WSL? [y/N] "
        read -r reply </dev/tty || reply=""
        case "$reply" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
    fi
fi

# ---- choose targets (lines of "label|skills dir") ---------------------------
TARGETS=""
add_target() { TARGETS="${TARGETS}$1|$2
"; }

if [ -n "$DEST" ]; then
    add_target "$DEST" "$DEST"
else
    if [ -z "$AGENTS" ]; then
        if can_prompt; then
            printf "${B}Install %s into which agents?${N}\n" "$SKILL_NAME"
            list_agents
            printf "Agent ids, comma-separated [Enter = all detected]: "
            read -r AGENTS </dev/tty || AGENTS=""
        fi
        # No choice given (Enter, or no terminal): install into every detected agent.
        [ -n "$AGENTS" ] || AGENTS="all"
    fi

    if [ "$AGENTS" = "all" ]; then
        # 'if' rather than '[ ] &&': under set -e, a final failed test would abort the script.
        AGENTS=$(agent_table | while IFS='|' read -r id _n detect _d; do
            if [ -d "$detect" ]; then printf "%s," "$id"; fi; done)
        [ -n "$AGENTS" ] || { err "no supported agents detected; use --agent or --dest"; exit 1; }
    fi

    for id in $(printf "%s" "$AGENTS" | tr ',' ' '); do
        dir=$(agent_field "$id" 4)
        if [ -z "$dir" ]; then
            err "unknown agent '$id'. Valid agents: $(agent_ids)all"
            exit 2
        fi
        add_target "$(agent_field "$id" 2)" "$dir"
    done
fi

# ---- uninstall --------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    printf "${B}Uninstalling %s${N}\n" "$SKILL_NAME"
    printf "%s" "$TARGETS" | while IFS='|' read -r label dir; do
        [ -n "$dir" ] || continue
        target="${dir:?}/$SKILL_NAME"
        if [ -e "$target" ] || [ -L "$target" ]; then
            run rm -rf "${target:?}"; ok "removed  $label ($target)"
        else
            warn "not installed in $label ($target)"
        fi
    done
    exit 0
fi

# ---- fetch and validate SKILL.md --------------------------------------------
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t broll)
trap 'rm -rf "$TMP"' 0
trap 'exit 1' 1 2 15

src=""
if [ "$REF_EXPLICIT" -eq 0 ] && [ -f "$0" ]; then
    script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
    [ -f "$script_dir/$SKILL_NAME/SKILL.md" ] && src="$script_dir/$SKILL_NAME/SKILL.md"
fi

if [ -n "$src" ]; then
    cp "$src" "$TMP/SKILL.md"
    echo "Source: local clone ($src)"
else
    url="https://raw.githubusercontent.com/$REPO/$REF/$SKILL_NAME/SKILL.md"
    echo "Source: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$TMP/SKILL.md" || { err "download failed"; exit 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TMP/SKILL.md" "$url" || { err "download failed"; exit 1; }
    else
        err "curl or wget is required to download the skill"; exit 1
    fi
fi

IFS= read -r first < "$TMP/SKILL.md" || first=""
first=$(printf "%s" "$first" | tr -d '\r')
if [ "$first" != "---" ] || ! grep -q "^name: $SKILL_NAME" "$TMP/SKILL.md"; then
    err "SKILL.md failed validation (missing frontmatter or wrong name); nothing installed"
    exit 1
fi

# ---- install ----------------------------------------------------------------
printf "${B}Installing %s${N}\n" "$SKILL_NAME"
installed=0; replaced=0; skipped=0
# Use a here-doc instead of a pipe so the counters survive the loop.
while IFS='|' read -r label dir; do
    [ -n "$dir" ] || continue
    target="${dir:?}/$SKILL_NAME"
    action="install "
    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ "$FORCE" -ne 1 ]; then
            warn "exists   $label ($target); use --force to replace"
            skipped=$((skipped + 1)); continue
        fi
        action="replace "
    fi
    run mkdir -p "$dir"
    stage="$dir/.$SKILL_NAME.tmp.$$"
    run rm -rf "${stage:?}"
    run mkdir -p "$stage"
    run cp "$TMP/SKILL.md" "$stage/SKILL.md"
    [ "$action" = "replace " ] && run rm -rf "${target:?}"
    run mv "$stage" "$target"
    ok "$action $label ($target)"
    if [ "$action" = "replace " ]; then replaced=$((replaced + 1)); else installed=$((installed + 1)); fi
done <<EOF
$TARGETS
EOF

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run, nothing changed: would install $installed, replace $replaced, skip $skipped."
else
    echo "Done: $installed installed, $replaced replaced, $skipped skipped."
fi

# ---- dependency check -------------------------------------------------------
# The skill shells out to these at run time, so check the PATH the agent will see.
printf "${B}Checking dependencies on PATH${N}\n"
missing=""
for dep in yt-dlp ffmpeg ffprobe; do
    if p=$(command -v "$dep" 2>/dev/null); then
        ok "found    $dep ($p)"
    else
        warn "missing  $dep"
        missing="$missing $dep"
    fi
done
if [ -n "$missing" ]; then
    printf "         The skill needs yt-dlp to download and ffmpeg/ffprobe to merge and check clips.\n"
    case "$(uname -s 2>/dev/null)" in
        Darwin)               printf "         Install: brew install yt-dlp ffmpeg\n" ;;
        MINGW*|MSYS*|CYGWIN*) printf "         Install (PowerShell): winget install yt-dlp.yt-dlp Gyan.FFmpeg\n" ;;
        *)                    printf "         Install: pipx install yt-dlp  and  sudo apt install ffmpeg (or your package manager)\n" ;;
    esac
    printf "         Then open a new terminal so the updated PATH is picked up.\n"
fi

if [ "$DRY_RUN" -eq 0 ] && { [ "$installed" -gt 0 ] || [ "$replaced" -gt 0 ]; }; then
    echo "Restart your agent, then ask it for b-roll or run /$SKILL_NAME."
fi
exit 0
