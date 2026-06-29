import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            Form {
                Section {
                    SecureField("Personal Access Token", text: $model.apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button {
                            Task { await model.saveCredentialAndRefresh() }
                        } label: {
                            Label("Save Token", systemImage: "checkmark.circle")
                        }
                        .disabled(model.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(role: .destructive) {
                            model.clearCredential()
                        } label: {
                            Label("Remove Token", systemImage: "trash")
                        }

                        Spacer()
                    }

                    if let user = model.user {
                        Text("\(user.displayName ?? user.email ?? user.userId) · \(user.projectCount) projects")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.statusMessage)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack(spacing: 5) {
                        Text("Credential")
                        InfoPopoverButton(
                            title: "Credential",
                            message: "The app stores one API token in macOS Keychain. It never logs the token, and project/device access is whatever the token is allowed to see."
                        )
                    }
                }

                Section {
                    TextField("Base URL", text: $model.baseURLString)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Disk budget")
                        InfoPopoverButton(
                            title: "Disk budget",
                            message: "Disk budget limits how much raw telemetry cache the app keeps locally. Aggregated run results and reports remain available after raw cache pruning."
                        )
                        Slider(value: $model.diskBudgetGB, in: 1...100, step: 1)
                        Text("\(Int(model.diskBudgetGB)) GB")
                            .frame(width: 56, alignment: .trailing)
                    }
                } header: {
                    HStack(spacing: 5) {
                        Text("API")
                        InfoPopoverButton(
                            title: "API",
                            message: "The base URL points to the Customer API. Change it only when testing another environment."
                        )
                    }
                }

                Section {
                    LabeledContent("Version", value: AppVersion.displayString)
                    Text("Version comes from the staged app bundle. Source releases use VERSION and BUILD at the repository root.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("App")
                }
            }
            .padding()
            .tabItem {
                Label("API", systemImage: "network")
            }

            Form {
                HStack {
                    Stepper("Reference windows: \(model.baselineWindowCount)", value: $model.baselineWindowCount, in: 1...12)
                    InfoPopoverButton(
                        title: "Reference windows",
                        message: "This controls how much prior history is required before the statistical baseline analyzer can make a stronger comparison. When history is insufficient, the app falls back to simpler threshold screens."
                    )
                }
                HStack {
                    Text("Minimum density")
                    InfoPopoverButton(
                        title: "Minimum density",
                        message: "Minimum density is the fraction of expected data that a reference window must contain before it can support baseline statistics."
                    )
                    Slider(value: $model.baselineDensity, in: 0.1...1.0, step: 0.05)
                    Text(Formatters.percent(model.baselineDensity))
                        .frame(width: 52, alignment: .trailing)
                }
            }
            .padding()
            .tabItem {
                Label("Analysis", systemImage: "chart.xyaxis.line")
            }
        }
        .frame(width: 560, height: 380)
    }
}
