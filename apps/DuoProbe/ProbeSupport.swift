import Foundation

// Small thread-safe helpers shared by every test. No mutable globals: each helper is an
// instance owned by one model, and the classes guard their state with an NSLock.

/// Seconds on the monotonic clock (the same base as CMSampleBuffer host times and
/// CMDeviceMotion.timestamp).
func uptimeNow() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}

/// Formats a number with a fixed number of decimals.
func fmt(_ value: Double, _ digits: Int = 2) -> String {
    String(format: "%.\(digits)f", value)
}

/// Seconds to whole milliseconds, as text.
func ms(_ seconds: Double) -> String {
    String(format: "%.0f", seconds * 1000)
}

/// Radians to degrees, as text.
func degText(_ radians: Double) -> String {
    String(format: "%.1f°", radians * 180 / Double.pi)
}

/// Something that happened on a background queue, with the time it happened.
struct ProbeEvent: Sendable {
    let t: TimeInterval
    let text: String
}

/// A queue that background threads append to and the main actor drains.
final class LockedQueue<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []

    func append(_ item: Element) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    func drain() -> [Element] {
        lock.lock()
        let out = items
        items.removeAll(keepingCapacity: true)
        lock.unlock()
        return out
    }
}

/// A single value shared between threads.
final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        let v = value
        lock.unlock()
        return v
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

/// Calls `body` on the main actor every `intervalMs` until stopped.
@MainActor
final class Poller {
    private var task: Task<Void, Never>?

    func start(intervalMs: UInt64 = 100, _ body: @escaping @MainActor @Sendable () -> Void) {
        stop()
        task = Task { @MainActor in
            while !Task.isCancelled {
                body()
                try? await Task.sleep(nanoseconds: intervalMs * 1_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// Appends text lines to a file from any thread, buffering a little.
final class CSVWriter: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private var buffer = ""
    private(set) var rows = 0

    init?(url: URL, header: String) {
        self.url = url
        guard let data = (header + "\n").data(using: .utf8) else { return nil }
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? h.seekToEnd()
        handle = h
    }

    func write(_ line: String) {
        lock.lock()
        buffer += line
        buffer += "\n"
        rows += 1
        if buffer.utf8.count > 32_000 {
            flushLocked()
        }
        lock.unlock()
    }

    func close() {
        lock.lock()
        flushLocked()
        try? handle?.close()
        handle = nil
        lock.unlock()
    }

    private func flushLocked() {
        guard !buffer.isEmpty, let data = buffer.data(using: .utf8) else { return }
        do {
            try handle?.write(contentsOf: data)
        } catch {
            // Nothing sensible to do mid-test; the row count in the log shows the loss.
        }
        buffer = ""
    }
}
