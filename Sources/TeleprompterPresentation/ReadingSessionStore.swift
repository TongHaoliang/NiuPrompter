import Foundation

/// Only the user's draft and reading cursor are persisted. Never recognized speech or audio.
public struct ScriptDocument: Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var text: String
    public var currentSegmentID: Int?
    public var promptSegmentID: Int?

    public init(title: String, text: String = "", currentSegmentID: Int? = nil, promptSegmentID: Int? = nil) {
        id = UUID()
        self.title = title
        self.text = text
        self.currentSegmentID = currentSegmentID
        self.promptSegmentID = promptSegmentID
    }
}

public struct ReadingSession: Codable, Equatable {
    public let version: Int
    public let text: String
    public let currentSegmentID: Int?
    public let promptSegmentID: Int?

    public let documents: [ScriptDocument]?
    public let activeDocumentID: UUID?

    public init(text: String, currentSegmentID: Int?, promptSegmentID: Int?, documents: [ScriptDocument]? = nil, activeDocumentID: UUID? = nil) {
        version = documents == nil ? 1 : 2
        self.documents = documents
        self.activeDocumentID = activeDocumentID
        self.text = text
        self.currentSegmentID = currentSegmentID
        self.promptSegmentID = promptSegmentID
    }
}

@MainActor
public protocol ReadingSessionStore {
    func load() throws -> ReadingSession?
    func save(_ session: ReadingSession) throws
}

@MainActor
public final class FileReadingSessionStore: ReadingSessionStore {
    private let url: URL
    public init(url: URL) { self.url = url }

    public static func applicationStore() -> FileReadingSessionStore {
        let root = URL.applicationSupportDirectory.appendingPathComponent("SmartTeleprompter", isDirectory: true)
        return FileReadingSessionStore(url: root.appendingPathComponent("reading-session.json"))
    }

    public func load() throws -> ReadingSession? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let session = try JSONDecoder().decode(ReadingSession.self, from: Data(contentsOf: url))
        guard session.version == 1 || session.version == 2 else { throw CocoaError(.coderReadCorrupt) }
        if session.version == 2 {
            guard let documents = session.documents, !documents.isEmpty,
                  Set(documents.map(\.id)).count == documents.count,
                  documents.contains(where: { $0.id == session.activeDocumentID }) else { throw CocoaError(.coderReadCorrupt) }
        }
        return session
    }

    public func save(_ session: ReadingSession) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(session)
        try data.write(to: url, options: .atomic)
    }
}
