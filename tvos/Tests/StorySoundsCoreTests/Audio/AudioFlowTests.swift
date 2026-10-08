import XCTest
@testable import StorySoundsCore

/// Speech interruption, completion waiting and case-safe audio ids.
@MainActor
final class AudioFlowTests: XCTestCase {
    private func make(_ entries: [AudioEntry]) -> (AudioPlaybackController, FakeBackend, FakeSpeech) {
        let backend = FakeBackend()
        let speech = FakeSpeech()
        let c = AudioPlaybackController(library: AudioFixtures.library(entries), backend: backend, speech: speech)
        return (c, backend, speech)
    }

    private let words: [AudioEntry] = [
        AudioFixtures.entry("w-cat", .word, label: "cat"),
        AudioFixtures.entry("w-dog", .word, label: "dog"),
        AudioFixtures.entry("ph-g-s", .phoneme, label: "/s/"),
        AudioFixtures.entry("w-i", .word, label: "I"),
    ]

    // MARK: Stop before speak

    func testNewSpeechAlwaysStopsInFlightSpeechFirst() {
        let (c, b, s) = make(words)
        _ = c.play("w-cat")
        _ = c.play("w-dog")
        XCTAssertEqual(s.events, ["stop", "speak:cat", "stop", "speak:dog"])
        XCTAssertGreaterThanOrEqual(b.stopped.filter { $0 == .narration }.count, 2)
    }

    func testRepeatedHearItAgainNeverQueuesUtterances() {
        let (c, _, s) = make(words)
        for _ in 0..<3 { _ = c.play("w-cat") }
        // Every speak is immediately preceded by a stop, so at most one utterance can exist at a time.
        for (i, e) in s.events.enumerated() where e.hasPrefix("speak:") {
            XCTAssertEqual(i > 0 ? s.events[i - 1] : "", "stop")
        }
        XCTAssertEqual(s.events.filter { $0.hasPrefix("speak:") }.count, 3)
    }

    func testStopAllStopsSpeechAndClearsNarrationState() {
        let (c, _, s) = make(words)
        _ = c.play("w-cat")
        XCTAssertTrue(c.isNarrationActive)
        c.stopAll()
        XCTAssertFalse(c.isNarrationActive)
        XCTAssertFalse(s.speaking)
    }

    func testSpeechCompletionCallbackEndsNarrationAndReturnsMachineToIdle() {
        let (c, _, s) = make(words)
        _ = c.play("w-cat")
        XCTAssertTrue(c.isNarrationActive)
        XCTAssertEqual(c.machine.state, .playing)
        s.finishNaturally()
        XCTAssertFalse(c.isNarrationActive)
        XCTAssertEqual(c.machine.state, .idle)
    }

    func testRecordedClipFinishEndsNarration() {
        let (c, b, _) = make([AudioFixtures.entry("w-cat", .word, file: "c.m4a", status: .recorded)])
        _ = c.play("w-cat")
        XCTAssertTrue(c.isNarrationActive)
        b.playing = false
        b.onChannelFinished?(.narration)
        XCTAssertFalse(c.isNarrationActive)
    }

    // MARK: Waiting for completion

    func testPlayAndWaitReturnsOnlyAfterTheClipFinishes() async {
        let (c, _, s) = make(words)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { s.finishNaturally() }
        let started = Date()
        let r = await c.playAndWait("w-cat", timeout: 5)
        XCTAssertEqual(r, .spokenPlaceholder(text: "cat"))
        XCTAssertFalse(c.isNarrationActive)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func testPlayAndWaitReturnsImmediatelyWhenOnlyACaptionIsShown() async {
        let (c, _, s) = make(words)
        let started = Date()
        let r = await c.playAndWait("ph-g-s", timeout: 5)
        XCTAssertEqual(r, .captionOnly(label: "/s/"))
        XCTAssertTrue(s.spoken.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testWaitGivesUpAtTheTimeoutIfCompletionIsNeverReported() async {
        let (c, _, _) = make(words)
        _ = c.play("w-cat")
        let started = Date()
        await c.waitForNarrationEnd(timeout: 0.2)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.15)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testStopAllReleasesAWaiter() async {
        let (c, _, _) = make(words)
        _ = c.play("w-cat")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { c.stopAll() }
        let started = Date()
        await c.waitForNarrationEnd(timeout: 5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testSequenceWaitsForEachClipBeforeStartingTheNext() async {
        let (c, _, s) = make(words)
        let finisher = Task { @MainActor in
            for _ in 0..<2 {
                var guardCount = 0
                while !s.speaking && guardCount < 500 { try? await Task.sleep(nanoseconds: 10_000_000); guardCount += 1 }
                try? await Task.sleep(nanoseconds: 30_000_000)
                s.finishNaturally()
            }
        }
        var shown: [String] = []
        await c.playSequenceAndWait(["w-cat", "ph-g-s", "w-dog"], gap: 0, captionDwell: 0, perResult: { id, _ in shown.append(id) })
        finisher.cancel()
        XCTAssertEqual(s.spoken.map { $0.0 }, ["cat", "dog"])
        XCTAssertEqual(shown, ["w-cat", "ph-g-s", "w-dog"])
        // Between the two utterances the first was already finished: no overlap.
        XCTAssertEqual(s.events, ["stop", "speak:cat", "stop", "speak:dog"])
    }

    func testSequenceStopsWhenTheTaskIsCancelled() async {
        let (c, _, s) = make(words)
        let task = Task { @MainActor in
            await c.playSequenceAndWait(["w-cat", "w-dog"], gap: 0, captionDwell: 0)
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        task.cancel()
        await task.value
        XCTAssertEqual(s.spoken.map { $0.0 }, ["cat"], "the second clip never starts after cancellation")
    }

    // MARK: Case-safe ids

    func testAudioIdsAreLowerCase() {
        XCTAssertEqual(AudioIds.word("I"), "w-i")
        XCTAssertEqual(AudioIds.word("Mrs"), "w-mrs")
        XCTAssertEqual(AudioIds.word("Zak"), "w-zak")
        XCTAssertEqual(AudioIds.word("cat"), "w-cat")
    }

    func testLibraryResolvesMixedCaseWordIdsToTheLowerCaseEntry() {
        let lib = AudioFixtures.library(words)
        XCTAssertNotNil(lib.entry(for: "w-I"))
        XCTAssertEqual(lib.resolve("w-I").source, .placeholder)
        XCTAssertEqual(lib.resolve("w-I").label, "I")
        XCTAssertEqual(lib.resolve("w-nope").source, .unknownId)
    }
}
