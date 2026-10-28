import Foundation

/// Pure helpers that turn recorded samples into per-close numbers.
enum CloseMath {
    struct DarkEvent {
        let darkT: Double       // first frame below 25% of the open brightness
        let halfT: Double       // first frame below 50% just before that
        let baseline: Double    // open brightness before the close
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Start of the gyro burst that ends at or before `end`: walks back from the last
    /// sample above `threshold` (rad/s) to the last quiet sample before it.
    static func motionStart(before end: Double, motion: [MotionSample],
                            threshold: Double = 0.5, window: Double = 3.0) -> Double? {
        let w = motion.filter { $0.t >= end - window && $0.t <= end + 0.05 }
        guard w.contains(where: { $0.rotationMagnitude >= threshold }) else { return nil }
        var i = w.count - 1
        while i >= 0 && w[i].rotationMagnitude < threshold { i -= 1 }
        while i >= 0 && w[i].rotationMagnitude >= threshold { i -= 1 }
        if i >= 0 { return w[i].t }
        return w.first?.t
    }

    /// Indices of samples where the angle first drops below `closedBelow` after having
    /// been above `openAbove` (radians).
    static func hingeCloses(_ s: [ProbeHingeSample], closedBelow: Double = 0.16, openAbove: Double = 0.5) -> [Int] {
        var out: [Int] = []
        var armed = false
        for (i, sample) in s.enumerated() {
            guard let a = sample.angle else { continue }
            if a > openAbove {
                armed = true
            } else if armed && a < closedBelow {
                out.append(i)
                armed = false
            }
        }
        return out
    }

    /// Last hinge sample before the angle started falling towards the close at `closeIndex`.
    static func hingeMotionStart(_ s: [ProbeHingeSample], closeIndex: Int) -> Double? {
        guard closeIndex >= 0 && closeIndex < s.count else { return nil }
        var i = closeIndex
        while i > 0 {
            guard let cur = s[i].angle, let prev = s[i - 1].angle else { break }
            if prev > cur + 0.003 {
                i -= 1
            } else {
                break
            }
        }
        return i < closeIndex ? s[i].t : nil
    }

    /// Brightness collapses: luma falls below 25% of a running "open" baseline.
    /// Re-arms once luma is back above 60% of that baseline.
    static func darkEvents(_ frames: [FrameSample]) -> [DarkEvent] {
        var out: [DarkEvent] = []
        var baseline: Double?
        var armed = true
        var history: [FrameSample] = []
        for f in frames where f.luma >= 0 {
            if let b = baseline {
                if armed {
                    if b > 12 && f.luma < 0.25 * b {
                        var halfT = f.t
                        for h in history.reversed() {
                            if h.luma >= 0.5 * b { break }
                            halfT = h.t
                        }
                        out.append(DarkEvent(darkT: f.t, halfT: halfT, baseline: b))
                        armed = false
                    } else if f.luma >= 0.5 * b {
                        baseline = 0.95 * b + 0.05 * f.luma
                    }
                } else if f.luma > 0.6 * b {
                    armed = true
                    baseline = f.luma
                }
            } else {
                baseline = f.luma
            }
            history.append(f)
            if history.count > 120 {
                history.removeFirst(history.count - 120)
            }
        }
        return out
    }

    /// Longest gap between consecutive times, in seconds.
    static func maxGap(_ times: [Double]) -> Double {
        guard times.count > 1 else { return 0 }
        var gap = 0.0
        for i in 1..<times.count {
            gap = max(gap, times[i] - times[i - 1])
        }
        return gap
    }
}

/// CSV sidecar: one row per motion sample (100 Hz) with the latest luma and hinge values.
enum Sidecar {
    static let header = "t,frame_t,luma,qw,qx,qy,qz,rot_x,rot_y,rot_z,acc_x,acc_y,acc_z,hinge_t,hinge_angle,hinge_status"

    @MainActor
    static func start(log: ProbeLog, testID: String, prefix: String, motion: MotionRecorder,
                      frameBox: LockedBox<FrameSample?>?, hingeBox: LockedBox<ProbeHingeSample?>?) -> CSVWriter? {
        let url = log.newFileURL(prefix: prefix, ext: "csv")
        guard let writer = CSVWriter(url: url, header: header) else {
            log.add(testID, "FAIL: couldn't create \(url.lastPathComponent)")
            return nil
        }
        motion.setHook { m in
            let f = frameBox?.get()
            let h = hingeBox?.get()
            var cols: [String] = [fmt(m.t, 4)]
            cols.append(f.map { fmt($0.t, 4) } ?? "")
            cols.append(f.map { fmt($0.luma, 1) } ?? "")
            cols.append(contentsOf: [m.qw, m.qx, m.qy, m.qz].map { fmt($0, 5) })
            cols.append(contentsOf: [m.rx, m.ry, m.rz, m.ax, m.ay, m.az].map { fmt($0, 4) })
            cols.append(h.map { fmt($0.t, 4) } ?? "")
            cols.append(h?.angle.map { fmt($0, 4) } ?? "")
            cols.append(h?.statusRaw.map { "\($0)" } ?? "")
            writer.write(cols.joined(separator: ","))
        }
        log.add(testID, "sensor CSV started: \(url.lastPathComponent) (times on the log's clock + \(fmt(log.startUptime, 3)) s)")
        return writer
    }

    @MainActor
    static func finish(_ writer: CSVWriter?, motion: MotionRecorder, log: ProbeLog, testID: String) {
        motion.setHook(nil)
        guard let w = writer else { return }
        w.close()
        log.add(testID, "sensor CSV closed: \(w.url.lastPathComponent), \(w.rows) rows")
        log.attach(w.url)
    }
}
