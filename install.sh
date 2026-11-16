#!/data/data/com.termux/files/usr/bin/bash
# Project name : Termux-YTD 2.0 (reviewed/fixed build)
# Coded by: Khansaad1275 — MIT Licence
# https://github.com/khansaad1275/Termux-YTD2.0

set -o pipefail

C_GRN=$'\e[032m'; C_YEL=$'\e[033m'; C_RED=$'\e[031m'; C_CYN=$'\e[034m'; C_OFF=$'\e[0m'
msg() { printf '%s%s%s\n' "$2" "$1" "$C_OFF"; }

msg "Updating default packages" "$C_CYN"
pkg update -y && pkg upgrade -y

msg "Requesting access to storage — tap Allow on the popup" "$C_GRN"
termux-setup-storage
sleep 3

msg "Installing python, ffmpeg and yt-dlp" "$C_CYN"
pkg install -y python
# ffmpeg is what merges the video stream with the audio stream.
# Without it yt-dlp saves two separate files — the bug this build fixes.
pkg install -y ffmpeg

if ! command -v pip >/dev/null 2>&1; then
  pkg install -y python-pip
fi
python -m pip install -U yt-dlp

msg "Creating the Youtube download folder" "$C_CYN"
mkdir -p "$HOME/storage/shared/Youtube"
mkdir -p "$HOME/bin"

msg "Installing termux-url-opener" "$C_CYN"
SRC_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -f "$HOME/bin/termux-url-opener" ]; then
  cp "$HOME/bin/termux-url-opener" "$HOME/bin/termux-url-opener.bak.$(date +%Y%m%d%H%M%S)"
  msg "Previous termux-url-opener backed up" "$C_YEL"
fi
cp "$SRC_DIR/termux-url-opener" "$HOME/bin/termux-url-opener"
chmod 755 "$HOME/bin/termux-url-opener"

msg "Verifying installation" "$C_CYN"
FAIL=0
for tool in yt-dlp ffmpeg; do
  if command -v "$tool" >/dev/null 2>&1; then
    msg "  ✔ $tool found" "$C_GRN"
  else
    msg "  ✖ $tool MISSING" "$C_RED"
    FAIL=1
  fi
done
[ -x "$HOME/bin/termux-url-opener" ] && msg "  ✔ termux-url-opener installed" "$C_GRN" || FAIL=1

echo
if [ "$FAIL" -eq 0 ]; then
  msg "Process complete!" "$C_GRN"
  msg "Share any YouTube video to Termux, pick a quality, and it downloads." "$C_GRN"
  msg "To update yt-dlp later:  python -m pip install -U yt-dlp" "$C_YEL"
  exit 0
else
  msg "Something is missing — see the ✖ lines above." "$C_RED"
  exit 1
fi
