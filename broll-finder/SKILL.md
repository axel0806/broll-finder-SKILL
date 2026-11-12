---
name: broll-finder
description: Use when the user asks to find, search for, grab, or download video clips, footage, or b-roll of a person, event, or topic from YouTube or the web with yt-dlp, into a folder for video editing.
---

# B-Roll Finder

## Overview
Use yt-dlp both to search and to download. B-roll needs footage of the subject itself, in short, edit-ready 1080p MP4 files. Choosing the clips is the step that takes judgment. Downloading is mechanical.

## Workflow

1. **Check the tools and the target folder** (on Windows, run this in PowerShell):
   ```powershell
   Get-ChildItem; (Get-Command yt-dlp).Source; (Get-Command ffmpeg).Source; yt-dlp --version
   ```
   If ffmpeg is missing, yt-dlp can't merge the video and audio streams. Tell the user.

2. **Search with several query angles.** Use the flat listing, which downloads nothing:
   ```powershell
   $q = "ytsearch8:<SUBJECT> keynote","ytsearch8:<SUBJECT> interview","ytsearch8:<SUBJECT> <event/context>"
   foreach ($s in $q) { yt-dlp --flat-playlist --print "%(id)s | %(duration_string)s | %(channel)s | %(title)s" $s }
   ```
   Pick angles that fit the subject: events, interviews, speeches, "highlights", "supercut".

3. **Choose clips** by following the rules below. Remove duplicates by ID.

4. **Download everything in one call:**
   ```powershell
   $ids = "ID1","ID2"; $urls = $ids | % { "https://www.youtube.com/watch?v=$_" }
   yt-dlp -f "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080]/b" --merge-output-format mp4 `
     -o "%(title)s [%(id)s].%(ext)s" --restrict-filenames --no-playlist --ignore-errors `
     --newline --progress-template "%(progress._percent_str)s" @urls 2>&1 |
     Select-String -NotMatch '^\s*\d+(\.\d+)?%$' | Select-Object -Last 40
   ```
   Set the timeout to the maximum (600000 ms). For large batches, run it in the background.

5. **Check the results.** Don't trust the log alone:
   ```powershell
   Get-ChildItem *.mp4 | % { $d = & ffprobe -v error -select_streams v:0 -show_entries stream=height:format=duration -of csv=p=0:s=x $_.FullName; "{0,8:N1} MB | {1} | {2}" -f ($_.Length/1MB), ($d -join ' '), $_.Name }
   ```

6. **Report** a table of clip names and lengths, plus the total size. List what you skipped and why, and offer to fetch it.

## Clip Selection Rules

| Include | Skip (mention in report) |
|---|---|
| Official channel highlights and supercuts | Full-length streams over about 60 min, unless the user asks for them |
| Keynote and stage moments, 1–25 min | AI-generated parodies or deepfakes, which don't show the real person |
| One or two longer interviews or documentaries with real footage | Gossip, scandal, or "talking-head anchor" news segments |
| Funny or viral moments featuring the subject | Reaction videos, music remixes, re-uploads of the same footage |

## Common Issues

| Symptom | Fix |
|---|---|
| `No supported JavaScript runtime could be found` | This is usually harmless, since 1080p still downloads. For 4K or missing formats, install deno and rerun. |
| Long download stalls the tool | Use `run_in_background`, or split the batch. |
| Bad characters in filenames | Add `--restrict-filenames`, which this skill already uses. |
| Separate `.f399.mp4` / `.m4a` files are left behind | ffmpeg is missing or the merge failed. Check that `ffmpeg` is on PATH. |
| User wants only a segment of a long video | `--download-sections "*12:30-14:00"` |
