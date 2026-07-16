# 🎙️ Whisper to Prompt

> **Talk. Prompt. Ship.** ⚡️

A local macOS voice assistant that turns your voice into prompts for **VS Code**, **Codex**, and any focused text field.

Built with Swift. Made for builders. Created by **7uro**. ✨

## ✨ What it does

1. Click into a prompt field
2. Say **“Codex”**, **“Test”**, or **“Start”**
3. Speak your prompt — it appears live ✍️
4. Say **“Over”** to finish or **“Submit”** to send 🚀

Works in German and English. Your audio stays on your Mac. 🔒

## 🍺 Install

### Homebrew

```sh
brew tap o7eanturo/tap
brew trust o7eanturo/tap
brew install --cask whisper-to-prompt
```

### Or download the app

Grab the latest `.dmg` from [Releases](https://github.com/o7eanturo/Whisper-to-Prompt/releases), open it, and drag **VoiceCodex.app** into **Applications**. Done. ✅

> **Beta heads-up:** the app currently uses `Handy.app` with a downloaded local speech model for transcription. Allow **Microphone** and **Accessibility** access when macOS asks.

## 🗣️ Voice commands

| Say this | What happens |
| --- | --- |
| `Codex` / `Test` / `Start` | Start dictating |
| `Over` / `Ende` / `Fertig` | Stop dictating |
| `Submit` / `Absenden` / `Senden` | Send the prompt |
| `Exit` / `Sleep` | Stop Voice Codex |

## 💻 For developers

```sh
git clone https://github.com/o7eanturo/Whisper-to-Prompt.git
cd Whisper-to-Prompt
Scripts/package-app.sh
```

The local app lands in `dist/VoiceCodex.app`.

## 🧠 Built local-first

- 🍎 Native Swift + macOS Accessibility APIs
- 🎧 Local microphone capture
- 🗣️ Local Handy speech model
- 🧩 Modular architecture — easy to extend

## 🤝 Open source

PRs, ideas, and bug reports are welcome. Let's make prompting feel natural. 🌍

Released under the [MIT License](LICENSE).
