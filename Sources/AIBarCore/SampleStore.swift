import Foundation
import os

/// Keeps one provider's usage samples on disk so the drain forecast survives app restarts.
///
/// Persistence is best effort: failures are logged, never thrown, because losing history only makes the forecast
/// start over, while an error would break the app.
public final class SampleStore: Sendable {
    public let fileURL: URL
    public let windowLength: TimeInterval
    private let cached: OSAllocatedUnfairLock<[UsageSample]>

    public init(fileURL: URL, windowLength: TimeInterval = 5 * 3600) {
        self.fileURL = fileURL
        self.windowLength = windowLength
        cached = OSAllocatedUnfairLock(initialState: Self.load(from: fileURL))
    }

    /// `~/Library/Application Support/AI Bar/samples-<provider>.json`; directories are created on first save.
    public static func defaultStore(for provider: ProviderID) -> SampleStore {
        let fileURL = URL.applicationSupportDirectory
            .appending(path: "AI Bar", directoryHint: .isDirectory)
            .appending(path: "samples-\(provider.rawValue).json", directoryHint: .notDirectory)
        return SampleStore(fileURL: fileURL)
    }

    /// Drops samples from before the current window first, so the file stays bounded. Without `resetsAt` the window
    /// start is unknown, so anything more than one window length older than `sample` is dropped instead.
    public func append(_ sample: UsageSample, resetsAt: Date?) {
        // Saving inside the lock keeps concurrent appends from overwriting the file with an older list.
        cached.withLock { samples in
            let windowStart = (resetsAt ?? sample.at).addingTimeInterval(-windowLength)
            samples.removeAll { $0.at < windowStart }
            samples.append(sample)
            save(samples)
        }
    }

    public func samples() -> [UsageSample] {
        cached.withLock { $0 }
    }

    public func clear() {
        cached.withLock { samples in
            samples.removeAll()
            save(samples)
        }
    }

    private static func load(from fileURL: URL) -> [UsageSample] {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return [] }
        do {
            return try JSONDecoder().decode([UsageSample].self, from: Data(contentsOf: fileURL))
        } catch {
            logger.error("Discarding unreadable usage samples at \(fileURL.path(percentEncoded: false), privacy: .public): \(error)")
            return []
        }
    }

    private func save(_ samples: [UsageSample]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(samples).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save usage samples to \(self.fileURL.path(percentEncoded: false), privacy: .public): \(error)")
        }
    }
}

private let logger = Logger(subsystem: "AIBar", category: "SampleStore")
