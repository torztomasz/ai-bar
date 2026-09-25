import Foundation
import os

/// Keeps one usage window's samples on disk so the drain forecast survives app restarts.
///
/// Persistence is best effort: failures are logged, never thrown, because losing history only makes the forecast
/// start over, while an error would break the app.
public final class SampleStore: Sendable {
    public let fileURL: URL
    public let windowLength: TimeInterval
    private let lockedSamples: OSAllocatedUnfairLock<[UsageSample]>

    public init(fileURL: URL, windowLength: TimeInterval = RollingWindow.fiveHours) {
        self.fileURL = fileURL
        self.windowLength = windowLength
        lockedSamples = OSAllocatedUnfairLock(initialState: Self.load(from: fileURL))
    }

    /// Stores `window`'s reading as observed at `now`. A window past its reset is skipped: the provider has not
    /// caught up, so the reading belongs to a window that is over and could skew the next one's pace.
    public func record(_ window: UsageWindow, at now: Date) {
        guard !window.isPastReset(now: now) else { return }
        append(UsageSample(at: now, percentUsed: window.percentUsed), resetsAt: window.resetsAt)
    }

    /// Keeps only samples inside the current window, `sample` included, so the file stays bounded. Without
    /// `resetsAt` the window start is unknown, so anything more than one window length older than `sample` goes.
    public func append(_ sample: UsageSample, resetsAt: Date?) {
        // Saving inside the lock keeps concurrent appends from overwriting the file with an older list.
        lockedSamples.withLock { samples in
            let windowStart = RollingWindow.start(resetsAt: resetsAt ?? sample.at, length: windowLength)
            samples.append(sample)
            samples.removeAll { $0.at < windowStart }
            save(samples)
        }
    }

    public func samples() -> [UsageSample] {
        lockedSamples.withLock { $0 }
    }

    public func clear() {
        lockedSamples.withLock { samples in
            samples.removeAll()
            save(samples)
        }
    }

    private static func load(from fileURL: URL) -> [UsageSample] {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return [] }
        do {
            return try JSONDecoder().decode([UsageSample].self, from: Data(contentsOf: fileURL))
        } catch {
            let path = fileURL.path(percentEncoded: false)
            logger.error("Discarding unreadable usage samples at \(path, privacy: .public): \(error)")
            return []
        }
    }

    private func save(_ samples: [UsageSample]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(samples).write(to: fileURL, options: .atomic)
        } catch {
            let path = fileURL.path(percentEncoded: false)
            logger.error("Could not save usage samples to \(path, privacy: .public): \(error)")
        }
    }
}

private let logger = Logger(subsystem: "com.torz.aibar", category: "SampleStore")
