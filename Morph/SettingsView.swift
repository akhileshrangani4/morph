import SwiftUI

/// Keys are pasted at runtime, so nothing secret is ever built into the binary
/// or committed to the repo.
struct SettingsView: View {
    @ObservedObject private var credentials = Credentials.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI") {
                    SecureField("sk-...", text: $credentials.openAIKey)
                        .textContentType(.password)
                    Text("Used for GPT-6 Astra over the Responses WebSocket.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Charming") {
                    SecureField("chrm_user_...", text: $credentials.charmingToken)
                        .textContentType(.password)
                    Text("A personal access token from your Charming account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Keys")
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
