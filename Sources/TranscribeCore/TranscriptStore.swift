import Foundation
import AVFoundation

public struct TranscriptStore: Sendable {
    public let root: URL
    public var projects: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    public var models: URL { root.appendingPathComponent("Models", isDirectory: true) }

    public init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Transcribe")
        for folder in [self.root, projects, models] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
        }
    }

    public func folder(_ id: UUID) -> URL { projects.appendingPathComponent(id.uuidString, isDirectory: true) }

    public func audioURL(_ transcript: Transcript) throws -> URL {
        guard !transcript.audioFilename.isEmpty,
              transcript.audioFilename == (transcript.audioFilename as NSString).lastPathComponent,
              transcript.audioFilename != ".", transcript.audioFilename != ".." else {
            throw TranscribeError.message("The saved recording has an invalid audio filename.")
        }
        return folder(transcript.id).appendingPathComponent(transcript.audioFilename)
    }

    public func createRecording() throws -> Transcript {
        let title = "Recording " + Date().formatted(date: .abbreviated, time: .shortened)
        let transcript = Transcript(title: title, audioFilename: "audio.m4a")
        try save(transcript)
        return transcript
    }

    public func importAudio(_ url: URL) async throws -> Transcript {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.fileFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw TranscribeError.message("This file contains no decodable audio.") }
        let ext = url.pathExtension.isEmpty ? "audio" : url.pathExtension.lowercased()
        let transcript = Transcript(title: url.deletingPathExtension().lastPathComponent,
                                    audioFilename: "audio.\(ext)", duration: duration)
        let directory = folder(transcript.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        do {
            try FileManager.default.copyItem(at: url, to: audioURL(transcript))
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: audioURL(transcript).path)
            try save(transcript)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return transcript
    }

    public func save(_ transcript: Transcript) throws {
        _ = try audioURL(transcript)
        let directory = folder(transcript.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("transcript.json")
        try Transcript.encoder.encode(transcript).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    @discardableResult
    public func trash(_ id: UUID) throws -> URL? {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: folder(id), resultingItemURL: &trashedURL)
        return trashedURL as URL?
    }

    public func loadAll() throws -> [Transcript] {
        var result: [Transcript] = []
        for directory in try FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            let url = directory.appendingPathComponent("transcript.json")
            let transcript = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: url))
            guard transcript.version == 1, transcript.id == id else {
                throw TranscribeError.message("Unsupported or inconsistent project at \(directory.path). Your files have been retained.")
            }
            _ = try audioURL(transcript)
            result.append(transcript)
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }
}
