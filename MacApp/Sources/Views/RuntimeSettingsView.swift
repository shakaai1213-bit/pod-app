import SwiftUI

struct RuntimeSettingsView: View {
    @Environment(OrcaMacModel.self) private var model
    @State private var serverAddress = ""
    @State private var token = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("Runtime") {
                TextField("Server", text: $serverAddress)
                    .textFieldStyle(.roundedBorder)
                SecureField(
                    model.hasStoredCredential ? "Credential stored" : "Agent credential",
                    text: $token
                )
                .textFieldStyle(.roundedBorder)
            }

            Section {
                HStack {
                    ConnectionDot(state: model.connectionState)
                    Text(model.connectionState.label)
                    Spacer()
                    Button(role: .destructive) {
                        Task { await model.removeCredential() }
                    } label: {
                        Label("Remove Credential", systemImage: "key.slash")
                    }
                    .disabled(!model.hasStoredCredential || isSaving)

                    Button {
                        isSaving = true
                        Task {
                            await model.saveConnection(serverAddress: serverAddress, token: token)
                            token = ""
                            isSaving = false
                        }
                    } label: {
                        Label("Connect", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { serverAddress = model.serverAddress }
    }
}
