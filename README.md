# Whisper to Prompt

Local macOS voice assistant for dictating prompts into VS Code, Codex chat, or any focused text input.

Created by `7uro`.

## Beta Notice

This is a beta build. Text insertion into input fields such as VS Code, Codex chat, and other prompt fields may not work reliably in every app or UI state yet.

## What It Does

`Whisper to Prompt` runs locally on your Mac and listens in two stages:

1. Waiting mode for a wake word like `Codex`, `Test`, or `Start`
2. Dictation mode for your actual prompt

When you finish speaking, the app can insert the recognized text into the last focused input field and optionally submit it.

## Current Voice Flow

1. Focus any text field, prompt field, or chat input
2. Open `Whisper to Prompt`
3. Click `Aufnahme starten`
4. Say `Codex`, `Test`, or `Start`
5. Dictate your prompt in German or English
6. Say `Over`, `End`, `Ende`, or `Fertig`
7. The app pastes the text into the previously focused input

Optional commands:

- `Submit`, `Absenden`, `Abschicken`, `Senden`: insert text and press Enter
- `Exit`, `Sleep`, `Schlafen`: stop the listening session completely

## Why This Stack

The project is built in Swift because it is the best fit for a reliable local macOS assistant:

- Native microphone and accessibility access
- Lower latency than a Python bridge for app control
- Better packaging as a real `.app`
- Easier long-term maintenance for a menu bar and desktop workflow

The current speech pipeline is local-first:

- Swift app shell for GUI and orchestration
- `WhisperKit` audio capture
- local `Handy` CLI transcription with an on-device German-capable model
- macOS Accessibility APIs for focusing and writing into text inputs

This avoids cloud speech services and keeps the workflow on-device.

## Architecture

```text
Sources/
  VoiceCodexCore/
    Domain.swift
    CommandParser.swift
    AssistantSession.swift

  VoiceCodexMac/
    VoiceCodexApp.swift
    VoiceCodexControlView.swift
    HandyCLITranscriber.swift
    AppleSpeechTranscriber.swift
    WhisperKitTranscriber.swift
    FocusedInputAccessibilityController.swift
    VSCodeAccessibilityController.swift

Resources/
  Info.plist

Scripts/
  package-app.sh

Tests/
  VoiceCodexCoreTests/
```

## Main Modules

- `Audio`: microphone capture and speech activity
- `Wake Word`: waiting state for `Codex`, `Test`, `Start`
- `Speech Recognition`: local transcription through Handy
- `Command Parser`: maps spoken commands to app actions
- `Input Controller`: pastes into the last focused accessible input
- `GUI`: small desktop control window for status, logs, and testing
- `Packaging`: builds a signed local macOS app bundle

## Current Behavior

- Local listening with microphone activity meter
- German and English trigger words
- Dictation preview in the GUI
- Insert into the last focused input field
- Optional submit via Enter
- Accessibility permission check
- Packaged app in `dist/VoiceCodex.app`

## Build And Start

```sh
swift build
chmod +x Scripts/package-app.sh
Scripts/package-app.sh
```

The packaged app will be created here:

```sh
dist/VoiceCodex.app
```

If you want to launch it manually:

```sh
open dist/VoiceCodex.app
```

## macOS Permissions

You need to allow:

- `Microphone`
- `Accessibility`

Path in macOS:

`System Settings -> Privacy & Security -> Accessibility`

Enable both:

- `VoiceCodex.app`
- `Visual Studio Code.app` if VS Code should accept automation cleanly

If accessibility gets stuck after rebuilding, reset it once:

```sh
tccutil reset Accessibility local.voicecodex.assistant
```

Then reopen the app and allow it again.

## How To Use It With VS Code Or Codex

The app does not need a custom VS Code API to be useful.

The current approach is:

1. Click into the target prompt or text field first
2. Start the voice app
3. Speak the wake word
4. Dictate
5. End with `Over` or submit with `Submit`

That means it can work not only with Codex chat, but also with many other accessible input fields.

## Status

This is a real modular app, not a one-file prototype.

Already working:

- wake word flow
- local speech recognition
- German commands
- GUI with status and recognition output
- insertion into focused inputs
- app packaging

Still good next steps:

- stronger focused-input diagnostics in the GUI
- more commands like `Continue`, `Clear`, `Cancel`
- better explicit support for Codex chat field detection
- optional menu bar only mode
- global hotkeys

## Repo Notes

Suggested repo name:

`whisper-to-prompt`

Alternative names:

- `voicecodex`
- `prompt-by-voice`
- `local-prompt-speaker`

If you want, this can also be published under a more branding-style name later while keeping the local app name as `Voice Codex`.
