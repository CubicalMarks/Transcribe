import SwiftUI

enum SettingsPage: Hashable {
    case models, summaries
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var sessionID = UUID()

    var body: some View {
        TabView(selection: $model.settingsPage) {
            ModelsView(model: model)
                .tabItem { Label("Local Models", systemImage: "cpu") }.tag(SettingsPage.models)
            SummarySettingsView(model: model)
                .id(sessionID)
                .tabItem { Label("Summarisation", systemImage: "text.badge.star") }.tag(SettingsPage.summaries)
        }
        .frame(width: 640, height: 660)
        // A new window session discards closed drafts; switching pages retains them.
        .onAppear { sessionID = UUID() }
        .onDisappear { model.chatGPT.cancel() }
    }
}
