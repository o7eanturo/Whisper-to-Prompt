#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
app="$root/dist/VoiceCodex.app"
plist="$root/Resources/Info.plist"
dist="$root/dist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
output="$dist/Whisper-to-Prompt-${version}.dmg"
stage="$(mktemp -d "${TMPDIR:-/tmp}/whisper-to-prompt-release.XXXXXX")"

cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT

OPEN_APP=0 "$root/Scripts/package-app.sh"

mkdir -p "$stage/Whisper to Prompt"
ditto "$app" "$stage/Whisper to Prompt/VoiceCodex.app"
ln -s /Applications "$stage/Whisper to Prompt/Applications"

if [[ -e "$output" ]]; then
  print -u2 "Release image already exists: $output"
  print -u2 "Increase CFBundleShortVersionString before creating another release."
  exit 1
fi

hdiutil create \
  -volname "Whisper to Prompt" \
  -srcfolder "$stage/Whisper to Prompt" \
  -format UDZO \
  "$output"

print "Created: $output"
print "SHA-256: $(shasum -a 256 "$output" | awk '{print $1}')"
