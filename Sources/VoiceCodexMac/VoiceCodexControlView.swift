import SwiftUI

struct VoiceCodexControlView: View {
    @ObservedObject var runtime: AssistantRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: runtime.symbolName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(runtime.isRunning ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice Codex").font(.title2.weight(.semibold))
                    Text(runtime.status)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            GroupBox("Steuerung") {
                HStack {
                    Button(runtime.isRunning ? "Aufnahme stoppen" : "Aufnahme starten") {
                        runtime.isRunning ? runtime.stop() : runtime.start()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Bedienungshilfen öffnen") {
                        runtime.requestAccessibilityAccess()
                    }
                }
                Button("Aktives Eingabefeld testen") {
                    runtime.testTargetInput()
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Label(
                runtime.accessibilityIsGranted
                    ? "VS-Code-Steuerung ist erlaubt"
                    : "VS-Code-Steuerung noch nicht erlaubt – fuer echtes Submit einmal freigeben",
                systemImage: runtime.accessibilityIsGranted ? "checkmark.shield.fill" : "exclamationmark.shield"
            )
            .font(.caption)
            .foregroundStyle(runtime.accessibilityIsGranted ? .green : .orange)

            Label(runtime.microphoneActivity, systemImage: runtime.isRunning ? "mic.fill" : "mic.slash")
                .font(.callout.weight(.medium))
                .foregroundStyle(runtime.isRunning ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Mikrofon-Pegel")
                    Spacer()
                    Text(runtime.audioLevel > 0.02 ? "Signal erkannt" : "Sprich zum Testen")
                        .foregroundStyle(runtime.audioLevel > 0.02 ? .green : .secondary)
                }
                .font(.caption)
                ProgressView(value: Double(runtime.audioLevel))
                    .tint(runtime.audioLevel > 0.02 ? .green : .blue)
            }

            GroupBox("Live-Erkennung") {
                Text(runtime.lastTranscription.isEmpty ? "Hier erscheint sofort, was verstanden wurde." : runtime.lastTranscription)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                    .textSelection(.enabled)
                    .foregroundStyle(runtime.lastTranscription.isEmpty ? .secondary : .primary)
                    .padding(.vertical, 4)
            }

            GroupBox("Gesammelter Prompt") {
                Text(runtime.currentDraft.isEmpty ? "Nach ‘Codex’ wird dein diktierter Prompt hier aufgebaut." : runtime.currentDraft)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .textSelection(.enabled)
                    .foregroundStyle(runtime.currentDraft.isEmpty ? .secondary : .primary)
                    .padding(.vertical, 4)
            }

            GroupBox("Sprachablauf") {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Sage „Codex“, „Test“ oder „Start“", systemImage: "1.circle")
                    Label("Diktiere deine Anfrage", systemImage: "2.circle")
                    Label("Sage „Over“/„Ende“ zum Einfügen oder „Submit“ zum Senden", systemImage: "3.circle")
                }
                .font(.callout)
                .padding(.vertical, 4)
            }

            Text("Lokale Erkennung nutzt das bereits installierte Handy-Modell. VS Code muss nur laufen und wird bei ‘Submit’ aktiviert.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
    }
}
