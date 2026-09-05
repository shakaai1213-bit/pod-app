import AuthenticationServices
import OrcaRuntimeContracts
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

            Section("Provider control") {
                if let records = model.providerControl?.records, !records.isEmpty {
                    ForEach(records, id: \.providerIdentity) { record in
                        ProviderControlRow(record: record)
                    }
                } else if model.isLoadingProviderControl {
                    ProgressView("Loading provider truth")
                } else {
                    Text(model.providerControlError ?? "No provider attestations are available.")
                        .font(.caption)
                        .foregroundStyle(model.providerControlError == nil ? Color.secondary : Color.red)
                }

                HStack {
                    if let generatedAt = model.providerControl?.generatedAt {
                        Text("ORCA · Cascade · \(generatedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.refreshProviderControl() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.connectionState.isReady || model.isLoadingProviderControl)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { serverAddress = model.serverAddress }
    }
}

private struct ProviderControlRow: View {
    let record: Components.Schemas.ChatRuntimeProviderControlRecordRead

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.executionAllowed ? "checkmark.circle.fill" : "pause.circle.fill")
                .foregroundStyle(record.executionAllowed ? Color.orcaGreen : Color.orcaAmber)
                .accessibilityLabel(record.executionAllowed ? "Available" : "Paused")

            VStack(alignment: .leading, spacing: 2) {
                Text(record.providerId)
                    .font(.body.weight(.medium))
                Text("\(record.executionHost.rawValue) · \(record.adapterId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.executionAllowed ? "Ready" : "Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.executionAllowed ? Color.orcaGreen : Color.orcaAmber)
                Text(record.lastDeliveryStatus == .failed ? "Delivery issue" : record.circuitState.rawValue)
                    .font(.caption2)
                    .foregroundStyle(record.lastDeliveryStatus == .failed ? Color.orcaAmber : .secondary)
            }
        }
        .help(record.statusReason)
    }
}

private extension Components.Schemas.ChatRuntimeProviderControlRecordRead {
    var providerIdentity: String { "\(executionHost.rawValue):\(adapterId)" }
}
