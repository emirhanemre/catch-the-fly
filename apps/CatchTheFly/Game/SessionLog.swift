import Foundation

/// The session log: FlyCore's log lines plus the app's own, appended to a text file in the
/// temporary folder about once a second. The Share button shares that file.
@MainActor
final class SessionLog {
    let fileURL: URL
    private var pending: [String] = []
    private var lastFlush: Double = 0
    private(set) var lineCount = 0
    private static let maxLines = 200_000

    init() {
        fileURL = FileManager.default.temporaryDirectory.appending(path: "CatchTheFly-session-log.txt")
        try? Data().write(to: fileURL)
    }

    func append(_ line: String) {
        guard lineCount < SessionLog.maxLines else { return }
        pending.append(line)
        lineCount += 1
    }

    func append(contentsOf lines: [String]) {
        for l in lines {
            append(l)
        }
    }

    func flushIfDue(now: Double) {
        if now - lastFlush >= 1.0 {
            lastFlush = now
            flush()
        }
    }

    func flush() {
        guard !pending.isEmpty else { return }
        let text = pending.joined(separator: "\n") + "\n"
        pending.removeAll()
        guard let data = text.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // The file vanished (temporary folder cleared): start it again.
            try? data.write(to: fileURL)
        }
    }
}
