import AuthenticationServices
import SwiftUI

struct RuntimeSettingsView: View {
    @Environment(OrcaMacModel.self) private var model
    @State private var serverAddress = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("Runtime") {
                TextField("Server", text: $serverAddress)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                HStack {
                    ConnectionDot(state: model.connectionState)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.connectionState.label)
                        if let detail = model.connectionDetail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await model.removeCredential() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(!model.hasStoredCredential || isSaving)

                    Button {
                        isSaving = true
                        Task {
                            await model.saveConnection(serverAddress: serverAddress)
                            isSaving = false
                        }
                    } label: {
                        Label("Use Server", systemImage: "network")
                    }
                    .disabled(isSaving || serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !model.hasStoredCredential {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            switch result {
                            case let .success(authorization):
                                Task { await model.completeAppleSignIn(authorization) }
                            case let .failure(error):
                                model.presentedError = error.localizedDescription
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(width: 190, height: 32)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { serverAddress = model.serverAddress }
    }
}
