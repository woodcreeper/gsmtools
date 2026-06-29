import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: AppSection? = .projects

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            DetailRouter(selection: selection ?? .devices)
        }
        .frame(minWidth: 1_280, minHeight: 760)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.refreshAccount() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)

                Button {
                    model.requestNewRunSetup()
                } label: {
                    Label("New Run", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
        .alert("GSMTools", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { _ in model.dismissError() }
        )) {
            Button("OK") {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: model.requestedSection) { _, requestedSection in
            guard let requestedSection else { return }
            selection = requestedSection
            model.requestedSection = nil
        }
    }
}

private struct DetailRouter: View {
    let selection: AppSection

    var body: some View {
        switch selection {
        case .devices:
            LifelineWorkspaceView()
        case .projects:
            ProjectBrowserView()
        case .runs:
            RunBuilderView()
        case .alerts:
            AlertCenterView()
        case .reports:
            ReportsView()
        }
    }
}
