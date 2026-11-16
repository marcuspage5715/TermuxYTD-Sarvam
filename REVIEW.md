# Code review — TermuxYTD-Sarvam

Reviewed files: `termux-url-opener` (83 lines), `install.sh` (40 lines), `README.md`.
Date: 17 November 2026. yt-dlp reference version: 2026.10.26.

---

## 0. First finding: the repo contains no modifications

`git diff` against `github.com/khansaad1275/Termux-YTD2.0` (the upstream original) is **empty** —
all four files are byte-identical. The single commit on `main` is "Update README.md" and it adds
the whole upstream tree at once.

So whatever you changed to make it "work for short videos" lives only on your phone, not in this
repository. Everything below is a review of the upstream code as pushed.

---

## 1. Why you get two files instead of one video

This is the main bug, and it is in `install.sh`.

`yt-dlp` never merges streams itself. It downloads a video-only stream and an audio-only stream
and then calls **ffmpeg** to mux them. `install.sh` installs `python` and `yt-dlp` but **never
installs ffmpeg**:

```bash
pkg install python -y
pip install yt-dlp
# ... and that's it
```

With no ffmpeg on the PATH, yt-dlp prints a warning and leaves
`Title.f137.mp4` (video) and `Title.f140.m4a` (audio) side by side. That is exactly the symptom
you describe. Shorts are small and often have a combined format, so the one-click path happens to
look fine there — which is why "it works for short videos".

Fix: `pkg install -y ffmpeg`, and refuse to start a download when it is missing.

---

## 2. Options 5 and 6 cannot give you 1080p or 4K

```bash
5)  yt-dlp -f 'best[height<=1080]' -o $fpath $1 ;;
6)  yt-dlp -f 'best[height<=2160]' -o $fpath $1 ;;
```

In yt-dlp's selector language, `best` means *the best single file that already contains both video
and audio*. On YouTube those legacy combined files only exist at 144p, 360p and 720p (formats 17,
18, 22). There is no combined 1080p or 2160p stream on YouTube at all.

Consequences:

- Option 5 (1080p) silently gives you 720p or 360p.
- Option 6 (2160p) does the same, or fails with `ERROR: Requested format is not available` on
  videos that have no combined format left.
- A >4 GB download therefore cannot have come from these options at all, unless your local copy
  differs from what is in the repo.

The correct selector requests the streams separately and lets ffmpeg join them:

```bash
-f 'bv*[height<=1080]+ba/b[height<=1080]'
```

`bv*` = best video (with or without audio), `ba` = best audio, `/b[height<=1080]` = fallback for
sites that only serve combined files. This is also the selector that exposes the missing-ffmpeg bug
from section 1, because now a merge is genuinely required.

---

## 3. Hard bugs in the script

| Line | Problem |
|------|---------|
| 81 | `-o $path $1` — `$path` is never defined (typo for `$fpath`). Unquoted, it disappears, so `-o` consumes the URL as its output template and yt-dlp receives no URL at all. The default branch (`*`) is completely broken. |
| 73 | `break` inside a `case`, outside any loop. bash prints `break: only meaningful in a for/while/until loop` and continues to the end of the script. Should be `exit 0`. |
| 15, 49–69, 81 | `-o $fpath $1` unquoted. Word splitting and pathname expansion apply. A share-intent URL containing a space, `*` or `?` (playlist links often do) breaks the command. Always `"$fpath"` and `"$1"`. |
| 14 | `[[ "$1" == *"shorts"* ]]` with no check that `$1` exists. Running the script with no argument silently falls through to the menu. |
| 9 | `fpath` hardcodes `/data/data/com.termux/files/home/...`. `$HOME` is the same path on a primary install but not on a secondary user profile. |
| — | No `--no-playlist`. Sharing a video that belongs to a playlist can start downloading the entire playlist. |
| — | No exit-status handling anywhere. |

## 4. Why it never "exits elegantly"

Three separate things combine into the feeling that the script gets lost:

1. **The exit code is thrown away.** `yt-dlp ...` is the last command in each branch; nothing reads
   `$?`. A failed download and a successful one end the same way — a fresh shell prompt. You cannot
   tell them apart.
2. **The merge phase is silent.** The progress bar reaches 100% when the *streams* finish
   downloading. Then ffmpeg remuxes two multi-gigabyte files, which on a phone takes minutes and
   prints nothing. The terminal looks frozen. That gap is what you are seeing on the big file.
3. **No log survives.** When the session closes, every message is gone.

A fixed script should capture `$?`, print `DOWNLOAD COMPLETE` with the filename and size, print
`DOWNLOAD FAILED (exit N)` plus the tail of the log otherwise, and keep the log in
`~/ytdl-last.log`. `--newline` makes progress lines readable instead of one overwritten line.

## 5. Large-file specifics (>4 GB)

- **4 GiB filesystem limit.** If `~/storage/shared` is a FAT32 volume (external SD card, or the
  shared partition on some older devices), no file larger than 4 GiB can be created. The `.part`
  file dies at exactly that point, mid-download, with an I/O error. Check with
  `mount | grep storage` — `vfat`/`fuseblk` means FAT.
- **Merge on FUSE/sdcardfs.** Android's shared storage is a FUSE layer. ffmpeg needs to seek and
  rewrite the output; on some devices this fails with `Operation not permitted` or produces a
  truncated file. Writing to internal storage (`$HOME`, ext4) and moving afterwards avoids it:
  `--paths temp:$HOME/.cache/ytdlp`.
- **Peak disk usage is ~3x the final size**: video stream + audio stream + merged output coexist
  until the merge finishes. A 4 GB video needs about 12 GB free. Nothing checks this today.
- **Retries.** On a mobile connection, `--retries 20 --fragment-retries 20 --retry-sleep 5`
  matters; the defaults (10) give up sooner than a flaky link deserves.
- **Filename length.** `%(title)s` for a long gaming-video title plus a long path can exceed the
  filesystem's limit. `%(title).150B` caps it.

## 6. `install.sh` issues

- `mkdir ~/storage/shared/Youtube` and `mkdir ~/bin` return an error if the directory already
  exists (second run). Use `mkdir -p`.
- `mv termux-url-opener ~/bin/` only works when the current directory is the repo, and it
  overwrites an existing opener with no backup.
- `apt update && apt upgrade -y` — Termux ships `pkg` as the wrapper; `apt upgrade` can stop on a
  configuration prompt. Use `pkg update -y && pkg upgrade -y`.
- `pip install yt-dlp` without `-U`, and pip is not guaranteed to exist (`pkg install python-pip`).
- yt-dlp goes stale within weeks; `yt-dlp -U` does **not** work for a pip install. The update
  command is `python -m pip install -U yt-dlp` and it is not documented anywhere.
- `echo -e "\e[032m" "text"` — the colour is passed as a separate argument, so the escape sequence
  terminates before the text and nothing is coloured. Cosmetic, but it is on almost every line.
- No verification step: nothing confirms ffmpeg, yt-dlp and the opener all ended up in place.
- If the user denies the storage prompt, `~/storage/shared` never appears and the failure surfaces
  only at download time.

## 7. README

Unmodified upstream: it points installation at `khansaad1275/Termux-YTD2.0`, lists no
requirements (notably not ffmpeg), and has no troubleshooting section. For a fork it should point
at your repo and document the 4 GB caveat.

---

## What was fixed in the delivered files

`termux-url-opener`
- ffmpeg is checked before anything runs; a missing ffmpeg aborts with an install command instead
  of quietly producing a split file.
- Every quality option now uses `bv*[height<=N]+ba/b[height<=N]`; a 1440p option was added and
  "Best available" is its own entry.
- `--merge-output-format mp4/mkv` so 4K AV1/VP9 + Opus merges to mkv when mp4 cannot hold it.
- `--no-playlist`, retries, `--concurrent-fragments 4`, `--newline`, `%(title).150B` template.
- Exit code captured via `PIPESTATUS`; prints `DOWNLOAD COMPLETE` with file and size, or
  `DOWNLOAD FAILED (exit N)` with the last 15 log lines; log kept at `~/ytdl-last.log`.
- Free-space warning; `mkdir -p`; every variable quoted; `break` → `exit 0`; `$path` typo gone;
  `USE_INTERNAL_TEMP=1` switch for the FUSE/FAT32 workaround.
- The session pauses before closing so the summary stays on screen.

`install.sh`
- Installs `ffmpeg` and `python-pip`, upgrades yt-dlp, uses `pkg` with `-y`, `mkdir -p`,
  backs up an existing opener, and verifies each tool at the end.

## Verification notes

- Both scripts pass `bash -n` and were exercised end to end against stub `yt-dlp`/`ffmpeg`
  binaries: success, non-zero exit, mp3, shorts, exit, invalid choice, missing-argument and
  missing-ffmpeg paths all behave as described.
- I could **not** query the live format list for `TX1c_Bc5J0Q`: YouTube answers this host with
  "Sign in to confirm you're not a bot". The selector analysis in sections 1–2 is based on
  yt-dlp's documented selector semantics, not on a live format dump of your video.
