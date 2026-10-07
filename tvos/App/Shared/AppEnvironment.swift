import Foundation
import SwiftUI
import StorySoundsCore
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Top-level navigation. Root screens (onboarding, home) deliberately let the system handle Menu (leaves the app).
enum Route: Equatable {
    case onboarding
    case home
    case baseline
    case session
    case summary(SessionSummary)
    case parent
}

/// Launch arguments understood by the app. They exist so UI tests are deterministic; real users never pass them.
///  - `-uitest-reset`          wipe every stored learner / setting at launch
///  - `-uitest-inmemory`       use in-memory stores (nothing is written to disk)
///  - `-uitest-reduce-motion`  behave as if Reduce Motion / gentle mode were on
///  - `-uitest-no-audio`       silent backend and no text-to-speech (captions only)
///  - `-uitest-fast-review`    treat "now" as +2 days (exercises delayed review)
///  - `-uitest-day-offset N`   treat "now" as +N days
struct LaunchOptions: Equatable {
    var reset = false
    var inMemory = false
    var reduceMotion = false
    var noAudio = false
    var dayOffset = 0

    init(arguments: [String] = []) {
        reset = arguments.contains("-uitest-reset")
        inMemory = arguments.contains("-uitest-inmemory")
        reduceMotion = arguments.contains("-uitest-reduce-motion")
        noAudio = arguments.contains("-uitest-no-audio")
        if arguments.contains("-uitest-fast-review") { dayOffset = 2 }
        if let i = arguments.firstIndex(of: "-uitest-day-offset"), i + 1 < arguments.count, let n = Int(arguments[i + 1]) {
            dayOffset = n
        }
    }
}

/// A backend that never produces sound (UI tests / `-uitest-no-audio`). Returning false from `play` makes the
/// controller fall back to captions, exactly like a missing recording.
final class SilentAudioBackend: AudioBackend {
    var onChannelFinished: ((AudioChannel) -> Void)?
    var isAnythingPlaying: Bool { false }
    func play(url: URL, channel: AudioChannel, volume: Float, rate: Float, loop: Bool) -> Bool { false }
    func stop(channel: AudioChannel) {}
    func stopAll() {}
    func pauseAll() {}
    func resumeAll() {}
    func setVolume(_ volume: Float, channel: AudioChannel) {}
}

/// THE integration point. The child UI and the parent UI both read and write learner state only through this object.
@MainActor
final class AppEnvironment: ObservableObject {
    // MARK: Content and audio
    let curriculum: Curriculum
    let index: CurriculumIndex
    let manifest: AudioManifest
    let library: AudioLibrary
    let audio: AudioPlaybackController

    // MARK: Storage (exposed for the parent area: backup, privacy, deletion)
    let store: LearnerStore
    let localKeyValue: KeyValueStoring
    let privacy: PrivacySettingsStore
    let backup: BackupService
    let coordinator: PersistenceCoordinator
    /// Household user scope. HOOK: when the app adopts tvOS user profiles, derive this from
    /// `TVUserManager` (TVServices) in `AppEnvironment.currentUserScope()` below. It is nil today, which means a
    /// single shared household profile. The scope only changes the storage key prefix; nothing else depends on it.
    let userScope: String?
    let options: LaunchOptions
    /// Non-nil when the bundled lessons could not be loaded. The root view then shows a friendly retry screen.
    let loadFailure: String?

    // MARK: Observable state
    @Published private(set) var snapshot: LearnerSnapshot
    @Published var route: Route
    /// Sound on/off for the whole app (kept separate from the volumes so turning it back on restores them).
    @Published private(set) var soundOn: Bool
    /// Caption for a sound that has no recording yet (phonemes are never synthesised). Auto-clears.
    @Published private(set) var soundCaption: String? = nil
    /// True after a save failed; the parent area can mention it. Cleared after a successful save.
    @Published private(set) var saveProblem = false

    private var sequenceTask: Task<Void, Never>?
    private var captionTask: Task<Void, Never>?
    private var sessionObserver: AnyObject?
    private static let soundKey = "storysounds.ui.soundOn"

    // MARK: Factory

    static func make(arguments: [String] = CommandLine.arguments) -> AppEnvironment {
        let options = LaunchOptions(arguments: arguments)
        var failure: String?
        var curriculum = AppEnvironment.emptyCurriculum()
        do {
            curriculum = try Curriculum.loadBundled()
        } catch {
            failure = "The stories could not be opened."
        }
        let manifest: AudioManifest = (try? AudioManifest.loadBundled()) ?? AppEnvironment.blankManifest()
        return AppEnvironment(options: options, curriculum: curriculum, manifest: manifest, failure: failure)
    }

    /// HOOK for tvOS household users (see `userScope`). Intentionally returns nil; TVServices is not imported.
    static func currentUserScope() -> String? { nil }

    private static func emptyCurriculum() -> Curriculum {
        Curriculum(schemaVersion: CurriculumSchema.version, contentVersion: "none", units: [], words: [],
                   trickyWords: [], sentences: [], stories: [])
    }

    private static func blankManifest() -> AudioManifest {
        let json = "{\"version\":1,\"statement\":\"\",\"entries\":[]}"
        do {
            return try JSONDecoder().decode(AudioManifest.self, from: Data(json.utf8))
        } catch {
            fatalError("Built-in constant manifest must decode")
        }
    }

    private static func freshSnapshot(contentVersion: String) -> LearnerSnapshot {
        let profile = LearnerProfile(id: UUID().uuidString, nickname: "Reader", createdAt: Date(), contentVersion: contentVersion)
        return LearnerSnapshot(profile: profile)
    }

    // MARK: Init

    private init(options: LaunchOptions, curriculum: Curriculum, manifest: AudioManifest, failure: String?) {
        let scope = AppEnvironment.currentUserScope()
        let kv: KeyValueStoring = options.inMemory ? InMemoryKeyValueStore() : UserDefaultsKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv, userScope: scope)
        let privacy = PrivacySettingsStore(keyValue: kv, userScope: scope)
        let backupService: BackupService
        if options.inMemory {
            backupService = ICloudKeyValueBackup(keyValue: InMemoryKeyValueStore(), privacy: privacy, availability: { false })
        } else {
            backupService = ICloudKeyValueBackup.makeDefault(privacy: privacy)
        }

        if options.reset {
            try? DataDeletionService(store: store, localKeyValue: kv, privacy: privacy, backup: nil).deleteEverything()
        }

        var loaded: LearnerSnapshot?
        if failure == nil {
            // Never reconcile (and therefore never save) against an empty fallback curriculum.
            if let id = (try? store.listProfileIds())?.first, let s = try? store.load(profileId: id) {
                loaded = Migrator.reconcile(s, with: curriculum).snapshot
            }
        }
        let snap = loaded ?? AppEnvironment.freshSnapshot(contentVersion: curriculum.contentVersion)

        let lib = AudioLibrary(manifest: manifest)
        let backend: AudioBackend = options.noAudio ? SilentAudioBackend() : AVAudioPlayerBackend()
        let speech: SpeechFallback? = options.noAudio ? nil : AVSpeechFallback()
        let controller = AudioPlaybackController(library: lib, backend: backend, speech: speech, settings: snap.profile.settings)

        var on = true
        if !options.inMemory, let stored = UserDefaults.standard.object(forKey: AppEnvironment.soundKey) as? Bool { on = stored }
        controller.isMuted = !on

        self.options = options
        self.userScope = scope
        self.curriculum = curriculum
        self.index = CurriculumIndex(curriculum)
        self.manifest = manifest
        self.library = lib
        self.audio = controller
        self.store = store
        self.localKeyValue = kv
        self.privacy = privacy
        self.backup = backupService
        self.coordinator = PersistenceCoordinator(store: store)
        self.loadFailure = failure
        self.snapshot = snap
        self.soundOn = on
        self.route = (loaded != nil) ? .home : .onboarding

        coordinator.onError = { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveProblem = true }
        }
        coordinator.onSaved = { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveProblem = false }
        }
        #if os(tvOS) || os(iOS) || os(visionOS)
        if !options.noAudio { sessionObserver = AVAudioSessionObserver(controller: controller) }
        #endif
    }

    // MARK: Time

    /// "Now" for planning and recording. Shifted by `-uitest-day-offset` / `-uitest-fast-review`.
    var now: Date { Date().addingTimeInterval(Double(options.dayOffset) * 86_400) }

    // MARK: Snapshot access

    /// Mutates the snapshot, publishes it and schedules a (debounced, compacted) save.
    func update(_ mutate: (inout LearnerSnapshot) -> Void) {
        var s = snapshot
        mutate(&s)
        snapshot = s
        if loadFailure == nil { coordinator.update(s) }
    }

    var settings: LearnerSettings { snapshot.profile.settings }

    func setSettings(_ newValue: LearnerSettings) {
        update { $0.profile.settings = newValue }
        audio.settings = newValue
    }

    /// True when motion should be removed everywhere: gentle mode on, or forced for tests.
    /// (Views also honour the system Reduce Motion setting through `accessibilityReduceMotion`.)
    var calmMotion: Bool { options.reduceMotion || snapshot.profile.settings.gentleMode }

    func setGentleMode(_ on: Bool) {
        var s = settings
        s.gentleMode = on
        setSettings(s)
    }

    func setSoundOn(_ on: Bool) {
        soundOn = on
        audio.isMuted = !on
        if !on { cancelSequence() }
        if !options.inMemory { UserDefaults.standard.set(on, forKey: AppEnvironment.soundKey) }
    }

    // MARK: Parent-facing helpers

    func explainUnits() -> [UnitExplanation] {
        Progression.explainUnits(index: index, snapshot: snapshot, now: now)
    }

    func parentReport() -> ParentReport {
        let explained = explainUnits()
        var statuses: [String: UnitStatus] = [:]
        for e in explained { statuses[e.unitId] = e.status }
        let current = Progression.nextUnit(index: index, snapshot: snapshot, now: now)?.id
        return ParentReport.make(curriculum: curriculum, snapshot: snapshot, now: now,
                                 inputs: ReportInputs(unitStatuses: statuses, currentUnitId: current))
    }

    /// Clears learning progress. Keeps profile id, nickname, creation date and settings.
    func resetProgress() {
        update { s in
            s.skills = []
            s.attempts = []
            s.confusions = []
            s.sessions = []
            s.profile.stickers = []
            s.profile.overrides = []
            s.profile.baselineDone = false
            s.profile.baselinePlacementOrder = nil
        }
        coordinator.flushNow()
    }

    /// Removes every learner snapshot, privacy setting and iCloud backup (DataDeletionService).
    /// On success the in-memory state is replaced by a fresh, UNSAVED profile; the caller decides when to move on
    /// (set `route = .onboarding`). Throws the first error so a grown-up is told the truth.
    func deleteEverything() throws {
        coordinator.cancelPending()
        cancelSequence()
        let service = DataDeletionService(store: store, localKeyValue: localKeyValue, privacy: privacy, backup: backup)
        try service.deleteEverything()
        let fresh = AppEnvironment.freshSnapshot(contentVersion: curriculum.contentVersion)
        snapshot = fresh
        soundOn = true
        audio.isMuted = false
        audio.settings = fresh.profile.settings
        saveProblem = false
    }

    /// Call when the scene becomes inactive or backgrounded.
    func flush() {
        if loadFailure == nil { coordinator.flushNow() }
    }

    func sceneLeftForeground() {
        flush()
        cancelSequence()
        audio.stopAll()
    }

    // MARK: Recording

    /// Folds one attempt into mastery, the attempt log and (for wrong choices) the confusion table.
    func recordAttempt(_ attempt: Attempt) {
        let masterySettings = snapshot.profile.settings.mastery
        let when = now
        update { s in
            if let i = s.skills.firstIndex(where: { $0.unitId == attempt.unitId && $0.track == attempt.track }) {
                s.skills[i] = Mastery.update(skill: s.skills[i], attempt: attempt, settings: masterySettings, now: when)
            } else {
                let fresh = SkillState(unitId: attempt.unitId, track: attempt.track)
                s.skills.append(Mastery.update(skill: fresh, attempt: attempt, settings: masterySettings, now: when))
            }
            s.attempts.append(attempt)
            if !attempt.correct, let expected = attempt.expected, let chosen = attempt.chosen, expected != chosen {
                if let c = s.confusions.firstIndex(where: { $0.expected == expected && $0.chosen == chosen }) {
                    s.confusions[c].count += 1
                    s.confusions[c].lastAt = when
                } else {
                    s.confusions.append(ConfusionRecord(expected: expected, chosen: chosen, count: 1, lastAt: when))
                }
            }
        }
    }

    /// Adds a sticker id to the profile when not already owned. Returns true when it was new.
    @discardableResult
    func awardSticker(_ id: String) -> Bool {
        if snapshot.profile.stickers.contains(id) { return false }
        update { $0.profile.stickers.append(id) }
        return true
    }

    func masteredUnitIds() -> Set<String> {
        Set(explainUnits().filter { $0.status == .mastered }.map { $0.unitId })
    }

    func phoneme(ofUnit unitId: String) -> String {
        index.unit(id: unitId)?.phoneme ?? ""
    }

    // MARK: Audio helpers

    @discardableResult
    func playAudio(_ id: String, slow: Bool = false) -> PlaybackResult {
        let result = audio.play(id, options: PlaybackOptions(slow: slow))
        if case let .captionOnly(label) = result, library.entry(for: id)?.kind == .phoneme {
            showSoundCaption(label)
        }
        return result
    }

    /// Plays ids one after another with fixed gaps (a new call replaces the previous one).
    func playSequence(_ ids: [String], slow: Bool = false) {
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor [weak self] in
            for id in ids {
                guard let strong = self, !Task.isCancelled else { return }
                strong.playAudio(id, slow: slow)
                let kind = strong.library.entry(for: id)?.kind
                let seconds: Double = (kind == .instruction) ? 1.8 : (kind == .phoneme ? 1.0 : 1.2)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func cancelSequence() {
        sequenceTask?.cancel()
        sequenceTask = nil
    }

    private func showSoundCaption(_ label: String) {
        soundCaption = label
        captionTask?.cancel()
        captionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { self?.soundCaption = nil }
        }
    }
}
