# B-Roll Finder (`broll-finder`)

A [Claude Code](https://claude.com/claude-code) skill for finding and downloading b-roll video clips of a person, event, or topic with yt-dlp, ready for video editing.

It guides Claude through four steps:
1. Search YouTube with several different queries.
2. Pick edit-ready clips. It skips full-length streams, AI deepfakes and parodies, and repeat uploads.
3. Download them all as 1080p MP4.
4. Check each file with ffprobe and report what was downloaded and what was skipped.

## Requirements
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/), including ffprobe
- Optional: [deno](https://deno.com/), for formats that need a JavaScript runtime

The example commands are written for PowerShell on Windows and are easy to adapt to bash.

## Install
Run this one-liner. No clone is needed:

```bash
curl -fsSL https://raw.githubusercontent.com/axel0806/broll-finder-SKILL/main/install.sh | sh -s -- --agent claude
```

Or install from a clone:

```bash
git clone https://github.com/axel0806/broll-finder-SKILL.git
cd broll-finder-SKILL
./install.sh            # asks which agents to install into
```

On Windows, run these commands in Git Bash or WSL.

### Supported agents
| `--agent` | Agent | Installs to |
|---|---|---|
| `claude` | Claude Code | `~/.claude/skills/broll-finder` |
| `codex` | Codex CLI | `~/.codex/skills/broll-finder` |
| `gemini` | Gemini CLI | `~/.gemini/skills/broll-finder` |
| `copilot` | GitHub Copilot CLI | `~/.copilot/skills/broll-finder` |
| `opencode` | OpenCode | `~/.config/opencode/skills/broll-finder` |
| `goose` | Goose | `~/.config/goose/skills/broll-finder` |
| `agents` | Generic cross-agent folder | `~/.agents/skills/broll-finder` |
| `all` | Every agent detected on this machine | |

You can pass several agents at once, comma-separated: `--agent claude,codex`.

### Options
| Flag | What it does |
|---|---|
| `--dest DIR` | Install into a custom parent skills directory |
| `--project` | Install into `./.claude/skills` in the current project |
| `--force` | Replace an existing install, for example to update |
| `--uninstall` | Remove the skill from the chosen agents |
| `--dry-run` | Show what would happen without changing anything |
| `--ref REF` | Install from a branch, tag or commit |
| `--list` | Show the supported agents and which ones are detected |

To update to the latest version, run `./install.sh --agent claude --force`. To remove the skill, run `./install.sh --agent claude --uninstall`.

## Usage
Restart your agent. Then ask something like *"find b-roll of <person> and download it into this folder"*, or run `/broll-finder`.

## Note
Only download content you have the right to use, and respect the platform's terms of service and the creators' copyright.
