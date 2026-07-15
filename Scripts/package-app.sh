#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

# macOS activates an already-running app instead of loading the freshly built
# executable. Stop the old helper first so every package run starts the code
# that was just compiled.
if pgrep -x voice-codex >/dev/null 2>&1; then
  pkill -x voice-codex || true
  for _ in {1..20}; do
    pgrep -x voice-codex >/dev/null 2>&1 || break
    sleep 0.1
  done
fi

swift build -c release

app="$root/dist/VoiceCodex.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/voice-codex" "$app/Contents/MacOS/voice-codex"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
# A plain ad-hoc signature uses the executable hash as its identity. That hash
# changes on every rebuild, so macOS Accessibility keeps trusting the previous
# binary while rejecting the new one. Embed a stable designated requirement
# based on our bundle identifier so local rebuilds keep the same TCC identity.
codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "local.voicecodex.assistant"' \
  "$app"
open "$app"
