import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var quitting = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting, let model else { return .terminateNow }
        quitting = true
        Task {
            let canQuit = await model.prepareToQuit()
            if !canQuit { quitting = false }
            sender.reply(toApplicationShouldTerminate: canQuit)
        }
        return .terminateLater
    }
}

@main struct TranscribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Transcribe", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 620)
                .onAppear { delegate.model = model; NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1160, height: 780)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Audio…", action: model.openFile).keyboardShortcut("o").disabled(model.locked)
                Button("Record Microphone", action: model.startRecording).keyboardShortcut("r").disabled(model.locked)
            }
            CommandGroup(after: .appSettings) {
                Button("Models…") { model.showModels = true }.keyboardShortcut(",")
                Button("Show Local Library") { NSWorkspace.shared.open(model.store.projects) }
                Button("Summary API Settings…") { model.showSummarySettings = true }.disabled(model.locked)
            }
        }
    }
}
