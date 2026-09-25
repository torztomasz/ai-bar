import Foundation
import Testing
@testable import AIBarCore

// Method: each test gets its own file in a fresh temp directory. Persistence is observed the way the app would see it
// after a restart: by opening a second store on the same file, never by reading the JSON directly.
@Suite final class SampleStoreBehavior {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    var fileURL: URL { directory.appending(path: "samples.json", directoryHint: .notDirectory) }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func samplesSurviveReopeningTheStore() {
        let first = UsageSample(at: start.addingTimeInterval(600), percentUsed: 10)
        let second = UsageSample(at: start.addingTimeInterval(1200), percentUsed: 12.5)
        let store = SampleStore(fileURL: fileURL)

        store.append(first, resetsAt: resetsAt)
        store.append(second, resetsAt: resetsAt)

        #expect(SampleStore(fileURL: fileURL).samples() == [first, second])
    }

    // Ten minutes before the window opened belongs to the previous window, so it is dropped from disk too.
    @Test func appendingDropsSamplesFromBeforeTheCurrentWindow() {
        let previousWindow = UsageSample(at: start.addingTimeInterval(-600), percentUsed: 80)
        let current = UsageSample(at: start.addingTimeInterval(600), percentUsed: 5)
        let store = SampleStore(fileURL: fileURL)

        store.append(previousWindow, resetsAt: start)
        store.append(current, resetsAt: resetsAt)

        #expect(store.samples() == [current])
        #expect(SampleStore(fileURL: fileURL).samples() == [current])
    }

    // With no reset time the window start is unknown, so anything more than one window length (5h) older than the
    // new sample is dropped: 5h10m old goes, 4h old stays.
    @Test func withoutAResetTimeAppendingDropsSamplesOlderThanOneWindow() {
        let newest = UsageSample(at: resetsAt, percentUsed: 0)
        let tooOld = UsageSample(at: resetsAt.addingTimeInterval(-5 * 3600 - 600), percentUsed: 40)
        let recent = UsageSample(at: resetsAt.addingTimeInterval(-4 * 3600), percentUsed: 50)
        let store = SampleStore(fileURL: fileURL)

        store.append(tooOld, resetsAt: nil)
        store.append(recent, resetsAt: nil)
        store.append(newest, resetsAt: nil)

        #expect(store.samples() == [recent, newest])
    }

    @Test func clearForgetsSamplesAcrossReopening() {
        let store = SampleStore(fileURL: fileURL)
        store.append(UsageSample(at: start.addingTimeInterval(600), percentUsed: 10), resetsAt: resetsAt)

        store.clear()

        #expect(store.samples().isEmpty)
        #expect(SampleStore(fileURL: fileURL).samples().isEmpty)
    }

    @Test func unreadableFileStartsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        #expect(SampleStore(fileURL: fileURL).samples().isEmpty)
    }

    // The store's directory is a regular file, so saving must fail; the sample is still kept for this session.
    @Test func failingToSaveKeepsSamplesInMemory() throws {
        try Data().write(to: directory)
        let sample = UsageSample(at: start.addingTimeInterval(600), percentUsed: 10)
        let store = SampleStore(fileURL: fileURL)

        store.append(sample, resetsAt: resetsAt)

        #expect(store.samples() == [sample])
    }

    // Only the location is checked, so the test never writes to the real history.
    @Test func defaultStoreKeepsOneFilePerProviderInApplicationSupport() {
        let store = SampleStore.defaultStore(for: ProviderID("claude"))
        let path = store.fileURL.path(percentEncoded: false)

        #expect(path.hasSuffix("/Library/Application Support/AI Bar/samples-claude.json"))
    }
}

private let resetsAt = Date(timeIntervalSince1970: 1_800_000_000)
private let start = resetsAt.addingTimeInterval(-5 * 3600)
