import SwiftUI

struct SpeakerNamesView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]
    @State private var speakerIDs: [Int] = []
    @State private var recordingID: UUID?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Speaker names").font(.title2.weight(.semibold))
            Text("Names apply to this recording. Voice labels are estimates; review them against the audio. Changes apply when you save.")
                .font(.body).foregroundStyle(.secondary)
            ForEach(speakerIDs, id: \.self) { id in
                TextField("Speaker \(id + 1)", text: Binding(get: { names[String(id)] ?? "" }, set: { names[String(id)] = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            if let message { Text(message).font(.body).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Names") {
                    guard let recordingID else { return }
                    do { try model.saveSpeakerNames(names, for: recordingID); dismiss() }
                    catch { message = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(model.locked || model.saveFailed)
            }
        }.padding(28).frame(width: 420)
            .onAppear {
                recordingID = model.selectedID
                names = model.selected?.speakerNames ?? [:]
                speakerIDs = model.selected?.speakerIDs ?? []
            }
    }
}
