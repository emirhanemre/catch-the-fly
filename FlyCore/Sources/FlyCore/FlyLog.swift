import Foundation

/// Deterministic text for the debug overlay and the session log.
/// Times are plain seconds on the game clock; no Date or locale formatting anywhere.
public enum FlyLog {

    /// Fixed-point text with exactly `decimals` digits after the point (0...9), rounding half away
    /// from zero. Examples: `fixed(1.5, decimals: 2) == "1.50"`, `fixed(-0.0004) == "0.000"`.
    /// Non-finite values give "nan", "inf" or "-inf".
    public static func fixed(_ value: Double, decimals: Int = 3) -> String {
        if value.isNaN { return "nan" }
        if value.isInfinite { return value > 0 ? "inf" : "-inf" }
        let d = max(0, min(decimals, 9))
        var scale: Int64 = 1
        var k = 0
        while k < d {
            scale *= 10
            k += 1
        }
        let scaled = (abs(value) * Double(scale)).rounded()
        if scaled >= 9.0e18 {
            return value > 0 ? "big" : "-big"
        }
        let n = Int64(scaled)
        let intPart = n / scale
        let fracPart = n % scale
        var s = ""
        if value < 0 && n != 0 {
            s = "-"
        }
        s += String(intPart)
        if d > 0 {
            var f = String(fracPart)
            while f.count < d {
                f = "0" + f
            }
            s += "." + f
        }
        return s
    }

    /// `"[12.345] TAG message"`.
    public static func line(time: Double, tag: String, message: String) -> String {
        let t = fixed(time, decimals: 3)
        return "[\(t)] \(tag) \(message)"
    }

    public static func describe(_ p: FlyScreenPoint?) -> String {
        guard let p = p else { return "none" }
        let x = fixed(p.x, decimals: 3)
        let y = fixed(p.y, decimals: 3)
        return "(\(x),\(y))"
    }

    public static func describe(_ v: Vec3) -> String {
        let x = fixed(v.x, decimals: 3)
        let y = fixed(v.y, decimals: 3)
        let z = fixed(v.z, decimals: 3)
        return "(\(x),\(y),\(z))"
    }

    /// `"wandering->landed arrived"`.
    public static func describe(_ t: FlyTransition) -> String {
        let from = t.from.rawValue
        let to = t.to.rawValue
        let why = t.reason.rawValue
        return "\(from)->\(to) \(why)"
    }

    /// `"source=hinge start=1.000 at=1.283 stalled=no"`.
    public static func describe(_ e: SmashEvent) -> String {
        let source = e.source.rawValue
        let start = fixed(e.motionStartTime, decimals: 3)
        let at = fixed(e.time, decimals: 3)
        let stalled = e.lumaStalled ? "yes" : "no"
        return "source=\(source) start=\(start) at=\(at) stalled=\(stalled)"
    }

    /// `"handOverLens"`.
    public static func describe(_ r: SmashRejection) -> String {
        return r.reason.rawValue
    }

    /// `"hit reason=hit judged=0.970 state=hovering dist=0.067 conf=1.00 screen=(0.710,0.500)"`.
    /// Without a snapshot: `"miss reason=noSnapshot judged=0.970"`.
    public static func describe(_ v: HitVerdict) -> String {
        let verdict = v.isHit ? "hit" : "miss"
        let reason = v.reason.rawValue
        let judged = fixed(v.judgedTime, decimals: 3)
        var s = "\(verdict) reason=\(reason) judged=\(judged)"
        if let snap = v.snapshot {
            let state = snap.flyState.rawValue
            let dist = optionalFixed(snap.distance, decimals: 3)
            let conf = fixed(snap.distanceConfidence, decimals: 2)
            let screen = describe(snap.screenPosition)
            s += " state=\(state) dist=\(dist) conf=\(conf) screen=\(screen)"
        }
        return s
    }

    /// `"dist=0.250 conf=1.00 rate=0.000"`.
    public static func describe(_ d: DistanceEstimate) -> String {
        let m = optionalFixed(d.metres, decimals: 3)
        let c = fixed(d.confidence, decimals: 2)
        let r = fixed(d.approachRate, decimals: 3)
        return "dist=\(m) conf=\(c) rate=\(r)"
    }

    /// `fixed(value)` or "none" for nil.
    public static func optionalFixed(_ value: Double?, decimals: Int = 3) -> String {
        guard let v = value else { return "none" }
        return fixed(v, decimals: decimals)
    }

    /// Lines for the debug overlay, from one frame's output.
    public static func overlayLines(_ out: FlyGameOutput) -> [String] {
        var lines: [String] = []
        let t = fixed(out.time, decimals: 2)
        lines.append("t=\(t)")
        if let fly = out.fly {
            let state = fly.state.rawValue
            var spot = "none"
            if let id = fly.spotID {
                spot = String(id)
            }
            let screen = describe(fly.screenPosition)
            lines.append("fly \(state) spot=\(spot) screen=\(screen)")
        } else {
            lines.append("fly none")
        }
        lines.append(describe(out.distance))
        let pan = fixed(out.audioPan, decimals: 2)
        let gain = fixed(out.audioGain, decimals: 2)
        lines.append("pan=\(pan) gain=\(gain)")
        let phase = out.round.phase.rawValue
        let caught = out.round.fliesCaught
        let total = out.round.fliesPerRound
        let elapsed = fixed(out.round.elapsed, decimals: 2)
        let best = optionalFixed(out.round.bestTime, decimals: 2)
        lines.append("round \(phase) \(caught)/\(total) time=\(elapsed) best=\(best)")
        return lines
    }
}
