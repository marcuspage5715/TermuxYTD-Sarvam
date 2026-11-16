# Termux-YTD 2.0 (fixed build)

A lightweight tool to download any YouTube video, music track or short with two taps on your
phone using Termux.

This is a fork of [khansaad1275/Termux-YTD2.0](https://github.com/khansaad1275/Termux-YTD2.0)
(MIT, © 2022 Saad Maqsood) with the bugs listed in [REVIEW.md](REVIEW.md) fixed.

## What changed in this fork

- **ffmpeg is now installed and required.** Without it yt-dlp cannot merge the video and audio
  streams and leaves you with two separate files. That was the main bug in the original.
- **The quality menu actually delivers the resolution it promises.** The original used
  `-f best[height<=N]`, which on YouTube can only ever return 144p, 360p or 720p. Every option now
  uses `bv*[height<=N]+ba/b[height<=N]`, and 1440p was added.
- **You can tell when a download is finished.** The script reports yt-dlp's exit code, prints
  `DOWNLOAD COMPLETE` with the file name and size (or `DOWNLOAD FAILED` with the log tail), and
  keeps a full log at `~/ytdl-last.log`.
- **Automatic retries.** A dropped connection no longer means coming back to restart by hand. The
  script retries up to 3 times with backoff (30 s, 2 min, 5 min), resuming from the partial file
  each time. Errors that retrying cannot fix — bad format, private or removed video, bot check —
  stop immediately instead of wasting your time.
- **Every download is verified with ffprobe.** After the merge, the script checks that the output
  has both a video and an audio stream and that its length matches the source (within 1%). A merge
  that got truncated can still play for a few minutes, so `DOWNLOAD COMPLETE` used to be a guess;
  now it says `verified with ffprobe` or fails with `VERIFICATION FAILED`.
- **`ytd-compat` for playback problems.** Converts a stuttering video to the H.264 / yuv420p /
  AAC combination Android decodes in hardware, remuxing instead of re-encoding when the codecs are
  already fine.
- **Fixed the broken default branch** (`-o $path` typo), the stray `break`, unquoted variables,
  missing `--no-playlist`, and the silent overwrite of an existing `termux-url-opener`.

## Requirements

Termux, plus `python`, `ffmpeg` and `yt-dlp`. `install.sh` installs all three.

## Installation

```bash
pkg install git
git clone https://github.com/marcuspage5715/TermuxYTD-Sarvam.git
cd TermuxYTD-Sarvam
bash install.sh
```

Allow the storage permission when the popup appears. When it finishes, `install.sh` verifies that
`yt-dlp`, `ffmpeg` and `~/bin/termux-url-opener` are all in place.

## Usage

1. In the YouTube app, tap Share on a video and choose **Termux**.
2. Pick a quality from the menu.
3. The video is written to `~/storage/shared/Youtube/`.

Shorts skip the menu and download at the best available quality.

Every download is merged into a single file. The last log is always at `~/ytdl-last.log`.

## Making a video play smoothly

The best quality YouTube offers is usually AV1 or VP9, sometimes 10-bit or 4:4:4. Many Android
players cannot hardware-decode those, so large videos stutter or play in slow motion. `ytd-compat`
converts a file to H.264 High / yuv420p / AAC in MP4, which every Android device decodes in
hardware:

```bash
ytd-compat video.mkv                  # writes video-compatible.mp4

ytd-compat video.mkv -o fixed.mp4     # choose the output name

ytd-compat --check video.mkv          # just report the codecs, change nothing
```

It is careful about the two traps in a hand-written ffmpeg command:

- Without `-pix_fmt yuv420p`, ffmpeg inherits the source's chroma layout and can produce **H.264
  High 4:4:4**, which phones do not decode. That is the usual reason a "fix" makes things worse.
- Without an explicit video codec, ffmpeg still re-encodes the video (it only copies streams with
  `-c copy`), so `-codec:a libmp3lame` is not an audio-only operation.

If the file already has H.264 / yuv420p / AAC and only the container is wrong (mkv), `ytd-compat`
remuxes with `-c copy` instead — lossless and seconds rather than hours. It refuses to overwrite an
existing file, removes a half-written output if you interrupt it, and checks the result with
ffprobe afterwards (codecs plus length against the source).

Re-encoding is slow: a multi-gigabyte file can take hours on a phone and loses a little quality.
Downloading an H.264 version in the first place is always cheaper.

## Troubleshooting

**I get two files, a video and an audio file.**
ffmpeg is missing. Run `pkg install -y ffmpeg` and check with `ffmpeg -version`. The current
`termux-url-opener` refuses to start a download when ffmpeg is absent, so you should see a clear
message instead of a split file.

**The video stutters or plays in slow motion.**
Run `ytd-compat --check yourfile.mp4`. If it reports anything other than `h264 (yuv420p)` / `aac`,
run `ytd-compat yourfile.mp4` to convert it. See "Making a video play smoothly" above.

**The download stopped by itself.**
Read the last lines the script prints, or `tail -n 30 ~/ytdl-last.log`. If it says "retrying in", it
handled a network error on its own and carried on. If it says "Permanent error", the video or the
chosen quality is the problem, not the connection — pick a lower quality or "Best available". If it
says "Giving up after 3 attempts", the connection was down for the whole backoff window; just share
the video again and it resumes from the partial file. Tune `MAX_ATTEMPTS` and `RETRY_WAITS` at the
top of `termux-url-opener` if you want more patience.

**It says `VERIFICATION FAILED`.**
The file downloaded but its length does not match the source, or a stream is missing — usually a
merge that got cut off by a full disk or a killed session. Delete that one file and share the video
again; yt-dlp resumes from what is left. If it fails the same way twice, the target filesystem is
the likely culprit (see the 4 GB entry below).

**The download dies at exactly 4 GB.**
`~/storage/shared` is on a FAT32 volume, which cannot hold a single file larger than 4 GiB. Check
with `mount | grep storage` — `vfat` or `fuseblk` confirms it. Download to internal storage
instead: set `USE_INTERNAL_TEMP=1` at the top of `termux-url-opener`, which stages the fragments in
`~/.cache/ytdlp` and moves the finished file afterwards. The final file still has to fit.

**The progress bar reaches 100% and then nothing happens for minutes.**
That is the merge step. yt-dlp hands two multi-gigabyte files to ffmpeg, which remuxes them with no
output. It is working, not hung. On a large video this can take several minutes.

**A big video fails with a disk-space or I/O error.**
Peak usage is roughly three times the final size, because the video stream, the audio stream and
the merged result all exist at once. Free up space first; the script warns when the target has less
than 8 GB free.

**`Requested format is not available`.**
The video does not offer that resolution. Pick a lower one, or "Best available". Also try
`python -m pip install -U yt-dlp` — YouTube changes break old yt-dlp versions within weeks.

**`Sign in to confirm you're not a bot`.**
YouTube is challenging the network rather than the video. Try a different connection, or pass
cookies with `--cookies-from-browser` if you have them.

## Keeping yt-dlp current

`yt-dlp -U` does not work for a pip install. Use:

```bash
python -m pip install -U yt-dlp
```

## Licence

MIT. Original work © 2022 Saad Maqsood
([khansaad1275/Termux-YTD2.0](https://github.com/khansaad1275/Termux-YTD2.0)).
