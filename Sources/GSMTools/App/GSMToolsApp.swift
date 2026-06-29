import AppKit
import SwiftUI

@main
struct GSMToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("GSMTools", id: "main") {
            ContentView()
                .environmentObject(model)
                .task {
                    await model.bootstrap()
                }
        }
        .commands {
            CommandMenu("Navigate") {
                ForEach(AppSection.allCases) { section in
                    Button(section.title) {
                        model.requestedSection = section
                    }
                    .keyboardShortcut(section.shortcutKey, modifiers: [.command])
                }
            }

            CommandMenu("GSMTools") {
                Button("Refresh Account") {
                    Task { await model.refreshAccount() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Load Sample Locations") {
                    Task { await model.loadSampleLocations() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
