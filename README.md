# downloading-broll-clips

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
Copy the skill folder into your personal skills directory:

```bash
git clone https://github.com/axel0806/downloading-broll-clips.git
cp -r downloading-broll-clips/downloading-broll-clips ~/.claude/skills/
```

Then ask Claude something like *"find b-roll of <person> and download it into this folder"*, or run `/downloading-broll-clips`.

## Note
Only download content you have the right to use, and respect the platform's terms of service and the creators' copyright.
