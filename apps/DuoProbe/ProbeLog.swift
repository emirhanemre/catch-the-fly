import Foundation
import SwiftUI

enum ResultKind: String, Sendable {
    case pass = "PASS"
    case fail = "FAIL"
    case value = "VALUE"
    case notAvailable = "N/A"
}

/// The one log for the whole session. Every line is timestamped in seconds since the app
/// started, on the monotonic clock, and written straight to a .txt file in the temporary
/// directory so a crash loses nothing.
@MainActor
final class ProbeLog: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var results: [String: String] = [:]
    @Published private(set) var attachments: [URL] = []
    /// Set in P2 when the tester marks "this one shows the room in front of me".
    @Published var testerPickedCameraID: String?
    @Published var testerPickedCameraName: String?

    let startUptime: TimeInterval
    let logURL: URL
    private var handle: FileHandle?
    private var fileCounter = 0

    init() {
        startUptime = ProcessInfo.processInfo.systemUptime
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DuoProbe-log-\(stamp).txt")
        logURL = url
        try? Data().write(to: url)
        handle = try? FileHandle(forWritingTo: url)
        add("LOG", "DuoProbe started \(Date()). Times are seconds since app start (monotonic clock).")
    }

    /// The log file plus every clip and CSV recorded so far.
    var shareItems: [URL] {
        [logURL] + attachments
    }

    func add(_ tag: String, _ message: String, at uptime: TimeInterval? = nil) {
        let t = (uptime ?? ProcessInfo.processInfo.systemUptime) - startUptime
        let line = "[" + String(format: "%9.3f", t) + "] " + tag + " " + message
        lines.append(line)
        if let data = (line + "\n").data(using: .utf8) {
            do {
                _ = try handle?.seekToEnd()
                try handle?.write(contentsOf: data)
            } catch {
                // Keep going: the on-screen log still has the line.
            }
        }
    }

    func result(_ test: String, _ kind: ResultKind, _ message: String) {
        add(test, "\(kind.rawValue): \(message)")
        results[test] = kind.rawValue
    }

    func answer(_ test: String, _ question: String, _ answer: String) {
        add(test, "ANSWER: \(question) -> \(answer)")
    }

    func system(_ message: String, at uptime: TimeInterval? = nil) {
        add("SYS", message, at: uptime)
    }

    /// A fresh file URL in the temporary directory, e.g. P9-walk-3.mov.
    func newFileURL(prefix: String, ext: String) -> URL {
        fileCounter += 1
        let rel = Int((ProcessInfo.processInfo.systemUptime - startUptime) * 10)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(rel)-\(fileCounter).\(ext)")
    }

    func attach(_ url: URL) {
        guard !attachments.contains(url) else { return }
        attachments.append(url)
        add("LOG", "Attached \(url.lastPathComponent) to the shared log")
    }
}
