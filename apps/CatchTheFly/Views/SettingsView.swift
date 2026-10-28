import SwiftUI

/// Settings sheet, opened from the start screen. Everything is kept in UserDefaults
/// (AppSettings); sensitivity changes reach FlyCore through GameController.refreshSensitivity().
struct SettingsView: View {
    @ObservedObject var game: GameController
    @ObservedObject var settings: AppSettings
    /// Called before the sheet closes; the start screen then shows the introduction.
    let onReplayOnboarding: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var bestWasReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Fly alarm", selection: $settings.alarmSensitivity) {
                        ForEach(AlarmSensitivity.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Text(settings.alarmSensitivity.detail)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                } header: {
                    Text("How jumpy the fly is")
                }

                Section {
                    Picker("Swat", selection: $settings.smashSensitivity) {
                        ForEach(SmashSensitivity.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Text(settings.smashSensitivity.detail)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                } header: {
                    Text("How readily a swat counts")
                } footer: {
                    Text("No setting ever asks you to fold or cover faster. A calm, normal-speed swat always works.")
                }

                Section {
                    Toggle("Sound", isOn: $settings.soundOn)
                    Toggle("Haptics", isOn: $settings.hapticsOn)
                } header: {
                    Text("Sound and feel")
                }

                Section {
                    Toggle("Debug overlay", isOn: $game.showDebug)
                } header: {
                    Text("For testing")
                } footer: {
                    Text("Shows the tracked patches, the hit region and the last swats over the camera picture.")
                }

                Section {
                    Button {
                        onReplayOnboarding()
                        dismiss()
                    } label: {
                        Label("Replay the introduction", systemImage: "play.circle")
                    }
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label(bestWasReset ? "Best time reset" : "Reset best time", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(bestWasReset)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Reset your best time?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) {
                    game.resetBestTime()
                    bestWasReset = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your splat gallery stays as it is.")
            }
            .onChange(of: settings.alarmSensitivity) { _, _ in
                game.refreshSensitivity()
            }
            .onChange(of: settings.smashSensitivity) { _, _ in
                game.refreshSensitivity()
            }
        }
    }
}
