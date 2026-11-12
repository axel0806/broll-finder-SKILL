#!/bin/sh
# install.sh: install the broll-finder skill into one or more coding agents.
#
# Usage:
#   ./install.sh                        # checklist menu (detected agents pre-selected)
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
    printf "  %-20s %-11s %s\n" "Agent" "--agent" "Status"
    agent_table | while IFS='|' read -r id name detect _dir; do
        if [ -d "$detect" ]; then s="${G}detected${N}"; else s="not found"; fi
        printf "  %-20s %-11s %b\n" "$name" "$id" "$s"
    done
}

# ---- interactive checklist --------------------------------------------------
# Arrow keys or j/k move, space toggles, a toggles all, enter confirms, q/esc cancels.
# Drawn on /dev/tty so it works under `curl | sh`. Sets MENU_RESULT to "id,id,".
tty_key() { dd bs=1 count="${1:-1}" 2>/dev/null </dev/tty | od -An -tx1 | tr -d ' \n'; }

menu_select() {
    m_title=$1
    m_n=0
    while IFS='|' read -r id name detect _d; do
        [ -n "$id" ] || continue
        m_n=$((m_n + 1))
        eval "m_id_$m_n=\$id; m_name_$m_n=\$name"
        if [ -d "$detect" ]; then eval "m_sel_$m_n=1; m_st_$m_n=detected"
        else eval "m_sel_$m_n=0; m_st_$m_n='not found'"; fi
    done <<EOF
$(agent_table)
EOF
    m_cur=1
    m_bold='\033[1m' m_dim='\033[2m' m_grn='\033[0;32m' m_rev='\033[7m' m_off='\033[0m'

    m_draw() {
        i=1
        while [ "$i" -le "$m_n" ]; do
            eval "nm=\$m_name_$i; s=\$m_sel_$i; st=\$m_st_$i"
            if [ "$s" = 1 ]; then box="${m_grn}[x]${m_off}"; else box="[ ]"; fi
            if [ "$st" = detected ]; then stc="${m_grn}detected${m_off}"; else stc="${m_dim}not found${m_off}"; fi
            if [ "$i" -eq "$m_cur" ]; then
                printf "\033[2K  ${m_bold}>${m_off} %b ${m_rev} %-20s ${m_off} %b\n" "$box" "$nm" "$stc"
            else
                printf "\033[2K    %b  %-20s  %b\n" "$box" "$nm" "$stc"
            fi
            i=$((i + 1))
        done
    }

    m_stty=$(stty -g </dev/tty)
    m_restore() { stty "$m_stty" </dev/tty 2>/dev/null; printf '\033[?25h' >/dev/tty; }
    trap 'm_restore; printf "\nCancelled, nothing changed.\n" >/dev/tty; exit 130' 1 2 15

    {
        printf "${m_bold}%s${m_off}\n" "$m_title"
        printf "${m_dim}up/down or j/k: move   space: select   a: all   enter: continue   q: cancel${m_off}\n"
        printf '\033[?25l'
        m_draw
    } >/dev/tty
    stty -icanon -echo min 1 time 0 </dev/tty

    while :; do
        k=$(tty_key)
        case "$k" in
            1b) # escape sequence (arrows) or a lone Esc
                stty min 0 time 1 </dev/tty; k2=$(tty_key 2); stty min 1 time 0 </dev/tty
                case "$k2" in
                    5b41|4f41) k=up ;;
                    5b42|4f42) k=down ;;
                    '')        k=quit ;;
                    *)         k=none ;;
                esac ;;
            6b|4b) k=up ;;      # k K
            6a|4a) k=down ;;    # j J
            20)    k=toggle ;;  # space
            61|41) k=all ;;     # a A
            ''|0a|0d) k=enter ;;
            71|51|03) k=quit ;; # q Q ctrl-c
            *)     k=none ;;
        esac
        case "$k" in
            up)     [ "$m_cur" -gt 1 ] && m_cur=$((m_cur - 1)) || m_cur=$m_n ;;
            down)   [ "$m_cur" -lt "$m_n" ] && m_cur=$((m_cur + 1)) || m_cur=1 ;;
            toggle) eval "s=\$m_sel_$m_cur"; if [ "$s" = 1 ]; then eval "m_sel_$m_cur=0"; else eval "m_sel_$m_cur=1"; fi ;;
            all)
                allon=1; i=1
                while [ "$i" -le "$m_n" ]; do eval "s=\$m_sel_$i"; [ "$s" = 1 ] || allon=0; i=$((i + 1)); done
                v=1; [ "$allon" = 1 ] && v=0
                i=1; while [ "$i" -le "$m_n" ]; do eval "m_sel_$i=$v"; i=$((i + 1)); done ;;
            enter)
                MENU_RESULT=""; i=1
                while [ "$i" -le "$m_n" ]; do
                    eval "s=\$m_sel_$i; id=\$m_id_$i"
                    if [ "$s" = 1 ]; then MENU_RESULT="$MENU_RESULT$id,"; fi
                    i=$((i + 1))
                done
                if [ -n "$MENU_RESULT" ]; then break; fi
                printf '\a' >/dev/tty ;;   # nothing selected: beep and stay
            quit)
                m_restore; trap - 1 2 15
                printf "Cancelled, nothing changed.\n" >/dev/tty
                exit 1 ;;
        esac
        { printf "\033[%dA" "$m_n"; m_draw; } >/dev/tty
    done

    m_restore; trap - 1 2 15
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
            if [ "$UNINSTALL" -eq 1 ]; then verb="Remove $SKILL_NAME from"; else verb="Install $SKILL_NAME into"; fi
            menu_select "$verb which agents?"
            AGENTS=$MENU_RESULT
        fi
        # No terminal (CI, piped input): use every detected agent.
        [ -n "$AGENTS" ] || AGENTS="all"
    fi

    if [ "$AGENTS" = "all" ]; then
        # 'if' rather than '[ ] &&': under set -e, a final failed test would abort the script.
        AGENTS=$(agent_table | while IFS='|' read -r id _n detect _d; do
            if [ -d "$detect" ]; then printf "%s," "$id"; fi; done)
        [ -n "$AGENTS" ] || { err "no supported agents detected; use --agent or --dest"; exit 1; }
    fi

    for id in $(printf "%s" "$AGENTS" | tr ',' ' ' | tr 'A-Z' 'a-z'); do
        dir=$(agent_field "$id" 4)
        if [ -z "$dir" ]; then
            err "unknown agent '$id'. Use one of: $(agent_ids)all  (see --list)"
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
