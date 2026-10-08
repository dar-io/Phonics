import Foundation

/// Source of parent-made recordings.
///
/// TODO (documented limitation): parent recording import on tvOS is not implemented. tvOS has no durable
/// Documents directory, no file sharing and no microphone recording UI, so recordings in Caches/tmp can be purged
/// by the OS. Until a durable route exists (e.g. CloudKit assets, opt-in), only bundled files are trusted and
/// this protocol is satisfied by an in-memory test double.
public protocol RecordingStore: AnyObject {
    func recordingURL(forAudioId id: String) -> URL?
    func audioIdsWithRecordings() -> Set<String>
}

public final class InMemoryRecordingStore: RecordingStore {
    private var urls: [String: URL] = [:]
    public init() {}
    public func set(_ url: URL?, forAudioId id: String) { urls[id] = url }
    public func recordingURL(forAudioId id: String) -> URL? { urls[id] }
    public func audioIdsWithRecordings() -> Set<String> { Set(urls.keys) }
}

/// Resolves an audio id to something playable. Order:
/// 1. bundled file from the manifest, when the entry is `recorded` or `verified` and the file exists in the bundle;
/// 2. a parent recording from the `RecordingStore`;
/// 3. placeholder (no sound: caller shows a caption, or placeholder speech for words/instructions only).
public final class AudioLibrary {
    public let manifest: AudioManifest
    private let entriesById: [String: AudioEntry]
    private let bundleResolver: (String) -> URL?
    private let recordings: RecordingStore?

    /// Pass `nil` for `bundleResolver` to look files up in this package's bundle.
    public init(manifest: AudioManifest, bundleResolver: ((String) -> URL?)? = nil,
                recordings: RecordingStore? = nil) {
        let bundleResolver = bundleResolver ?? AudioLibrary.bundleResolver(bundle: .module)
        self.manifest = manifest
        var dict: [String: AudioEntry] = [:]
        for e in manifest.entries { dict[e.id] = e }
        self.entriesById = dict
        self.bundleResolver = bundleResolver
        self.recordings = recordings
    }

    /// Looks up `file` ("name.m4a" or "dir/name.m4a") in a bundle.
    public static func bundleResolver(bundle: Bundle) -> (String) -> URL? {
        return { file in
            let ns = file as NSString
            let dir = ns.deletingLastPathComponent
            let last = ns.lastPathComponent as NSString
            let name = last.deletingPathExtension
            let ext = last.pathExtension.isEmpty ? nil : last.pathExtension
            if !dir.isEmpty, let u = bundle.url(forResource: name, withExtension: ext, subdirectory: dir) { return u }
            return bundle.url(forResource: name, withExtension: ext)
        }
    }

    /// Exact id first, then the lower-cased id (word ids are lower-case in the manifest; see `AudioIds`).
    public func entry(for id: String) -> AudioEntry? { return entriesById[id] ?? entriesById[id.lowercased()] }

    public func resolve(_ id: String) -> ResolvedAudio {
        guard let e = entry(for: id) else {
            return ResolvedAudio(id: id, kind: nil, label: id, status: nil, source: .unknownId, url: nil, slowURL: nil)
        }
        if e.status != .placeholder, let f = e.file, let url = bundleResolver(f) {
            return ResolvedAudio(id: id, kind: e.kind, label: e.label, status: e.status, source: .bundledFile,
                                 url: url, slowURL: e.slowFile.flatMap(bundleResolver))
        }
        if let rec = recordings?.recordingURL(forAudioId: id) {
            return ResolvedAudio(id: id, kind: e.kind, label: e.label, status: .recorded, source: .parentRecording, url: rec, slowURL: nil)
        }
        return ResolvedAudio(id: id, kind: e.kind, label: e.label, status: .placeholder, source: .placeholder, url: nil, slowURL: nil)
    }

    public func statusReport() -> AudioStatusReport {
        AudioStatusReport.make(resolved: manifest.entries.map { resolve($0.id) })
    }
}

/// For the parent audio screen: how much of the audio is real.
public struct AudioStatusReport: Equatable, Sendable {
    public struct Counts: Equatable, Sendable {
        public var placeholder = 0, recorded = 0, verified = 0
        public var total: Int { placeholder + recorded + verified }
        public init() {}
    }
    public static let disclaimer = "Sounds and words in this app are placeholders or home-made recordings. They are not Little Wandle approved or endorsed. Isolated sounds are never computer-generated."

    public let byKind: [AudioKind: Counts]
    public let parentRecordingCount: Int

    public var total: Counts {
        var c = Counts()
        for v in byKind.values { c.placeholder += v.placeholder; c.recorded += v.recorded; c.verified += v.verified }
        return c
    }
    public func counts(for kind: AudioKind) -> Counts { byKind[kind] ?? Counts() }
    public var isAllPlaceholder: Bool { let t = total; return t.total > 0 && t.recorded == 0 && t.verified == 0 }

    public static func make(resolved: [ResolvedAudio]) -> AudioStatusReport {
        var by: [AudioKind: Counts] = [:]
        var parent = 0
        for r in resolved {
            guard let k = r.kind else { continue }
            var c = by[k] ?? Counts()
            switch r.status ?? .placeholder {
            case .placeholder: c.placeholder += 1
            case .recorded: c.recorded += 1
            case .verified: c.verified += 1
            }
            by[k] = c
            if r.source == .parentRecording { parent += 1 }
        }
        return AudioStatusReport(byKind: by, parentRecordingCount: parent)
    }

    /// Human-readable lines such as "Sounds: 94 placeholder, 0 recorded, 0 verified".
    public var summaryLines: [String] {
        let names: [(AudioKind, String)] = [(.phoneme, "Sounds"), (.word, "Words"), (.instruction, "Instructions"), (.sfx, "Effects")]
        return names.map { kind, name in
            let c = counts(for: kind)
            return "\(name): \(c.placeholder) placeholder, \(c.recorded) recorded, \(c.verified) verified"
        }
    }
}
