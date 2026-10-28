import Foundation

/// Mirror of `UIHinge.Status`, so FlyCore needs no UIKit.
public enum HingeStatus: String, Sendable, Equatable, CaseIterable {
    case closed
    case partiallyOpen
    case fullyOpen
}

/// How the raw integer of `UIHinge.status` (ObjC `NS_ENUM UIHingeStatus : NSInteger`) maps to `HingeStatus`.
///
/// The integer values are undocumented (API_NOTES section 1, DUO_FACTS): spike P5 logs them. Until then
/// `FlyTunables.hingeStatusMapping` holds `declarationOrderGuess`; once P5 has the real numbers, set the
/// tunable (or this guess) and nothing else changes. A raw value that matches no case, or matches
/// `unknown`, maps to nil (status unknown: the detector then uses the angle alone).
public struct HingeStatusMapping: Sendable, Equatable {
    public var closed: Int?
    public var partiallyOpen: Int?
    public var fullyOpen: Int?
    /// The raw value of `UIHingeStatusUnknown`. It always maps to nil; listing it documents the guess.
    public var unknown: Int?

    public init(closed: Int?, partiallyOpen: Int?, fullyOpen: Int?, unknown: Int?) {
        self.closed = closed
        self.partiallyOpen = partiallyOpen
        self.fullyOpen = fullyOpen
        self.unknown = unknown
    }

    /// Guess (unverified until P5): an `NS_ENUM` without explicit values numbers its constants from 0
    /// in declaration order, and Apple's docs list the cases as closed, partiallyOpen, fullyOpen,
    /// unknown (not alphabetical, so presumably declaration order): closed 0, partiallyOpen 1,
    /// fullyOpen 2, unknown 3. Neither DuoProbe nor the game assumes any value; both log the raw integer.
    public static let declarationOrderGuess = HingeStatusMapping(closed: 0, partiallyOpen: 1, fullyOpen: 2, unknown: 3)

    /// Maps nothing: every raw status is unknown, so only the angle counts.
    public static let ignoreStatus = HingeStatusMapping(closed: nil, partiallyOpen: nil, fullyOpen: nil, unknown: nil)

    /// The status for a raw value, or nil when `raw` is nil, is `unknown`, or matches no case.
    /// If two cases share a raw value, the first of closed, partiallyOpen, fullyOpen wins.
    public func status(forRaw raw: Int?) -> HingeStatus? {
        guard let r = raw else { return nil }
        if let u = unknown, u == r { return nil }
        if let c = closed, c == r { return .closed }
        if let p = partiallyOpen, p == r { return .partiallyOpen }
        if let f = fullyOpen, f == r { return .fullyOpen }
        return nil
    }

    /// The raw value this mapping gives `status`, nil if none.
    public func rawValue(for status: HingeStatus) -> Int? {
        switch status {
        case .closed: return closed
        case .partiallyOpen: return partiallyOpen
        case .fullyOpen: return fullyOpen
        }
    }
}

/// One hinge reading. `angle` in radians, 0 = shut, pi = flat. `time` in seconds on the game clock.
///
/// `status` is the mapped status if the app already knows it. Otherwise pass the raw `UIHinge.status`
/// integer as `statusRaw` and leave `status` nil: SmashDetector maps it with `tunables.hingeStatusMapping`
/// (a mapped `.closed` only counts while the angle is below `hingeArmAngle`, since the mapping is a guess).
public struct HingeSample: Sendable, Equatable {
    public var angle: Double
    public var time: Double
    public var status: HingeStatus?
    /// The raw `UIHinge.status` integer, nil if not read.
    public var statusRaw: Int?

    public init(angle: Double, time: Double, status: HingeStatus? = nil, statusRaw: Int? = nil) {
        self.angle = angle
        self.time = time
        self.status = status
        self.statusRaw = statusRaw
    }

    /// `status` if set, else `statusRaw` mapped with `mapping`.
    public func resolvedStatus(_ mapping: HingeStatusMapping) -> HingeStatus? {
        if let s = status { return s }
        return mapping.status(forRaw: statusRaw)
    }
}

/// One camera brightness reading: mean luma of a frame, 0 (black) to 1 (white).
public struct LumaSample: Sendable, Equatable {
    public var mean: Double
    public var time: Double

    public init(mean: Double, time: Double) {
        self.mean = mean
        self.time = time
    }
}

/// Which evidence produced a smash.
public enum SmashSource: String, Sendable, Equatable, CaseIterable {
    /// The hinge folded shut.
    case hinge
    /// The camera went dark (no hinge API).
    case luma
    /// The camera went dark and the hinge confirmed it was moving.
    case hingeAndLuma
    /// A debug button.
    case manual
}

/// A detected smash.
public struct SmashEvent: Sendable, Equatable {
    /// When the detector decided (s).
    public var time: Double
    /// Best estimate of when the fold began (s). HitJudge judges the game state at this time.
    public var motionStartTime: Double
    public var source: SmashSource
    /// True if the luma evidence was a stream that stopped while dropping (capture interrupted).
    public var lumaStalled: Bool

    public init(time: Double, motionStartTime: Double, source: SmashSource, lumaStalled: Bool = false) {
        self.time = time
        self.motionStartTime = motionStartTime
        self.source = source
        self.lumaStalled = lumaStalled
    }
}

/// Why a possible smash was turned down (for the debug overlay and log).
public enum SmashRejectReason: String, Sendable, Equatable, CaseIterable {
    /// Within `smashDebounce` of the previous smash.
    case debounced
    /// Dark camera, but the hinge did not move: a hand over the lens.
    case handOverLens
    /// The hinge closed too slowly or took too long.
    case closeTooSlow
    /// The hinge closed from a nearly shut position (folded through less than `hingeMinCloseDrop`).
    case closeTooSmall
    /// Without a hinge, the camera darkened too slowly (or was never lit in the lookback).
    case collapseTooSlow
    /// Without a hinge, a stopped luma stream was the only evidence and `lumaStallCountsAlone` is false.
    case stallOnly
}

public struct SmashRejection: Sendable, Equatable {
    public var time: Double
    public var reason: SmashRejectReason

    public init(time: Double, reason: SmashRejectReason) {
        self.time = time
        self.reason = reason
    }
}

/// Turns hinge and camera-brightness streams into smash events.
///
/// Paths:
/// - Hinge: the angle reaches `hingeClosedAngle` (or status `.closed`) after a close that began at or
///   above `hingeArmAngle`, folded through at least `hingeMinCloseDrop`, and averaged at least
///   `smashMinAngularSpeed` within `closeMaxDuration`. Works with as few as two samples per close:
///   the motion start is estimated as `max(lastStillSampleTime, firstMovingSampleTime - firstDrop / smashNominalAngularSpeed)`.
/// - Luma with hinge available: darkness (or a stream that stopped while dropping) only counts once the
///   hinge confirms it fell by `hingeCorroborationDrop` within `hingeCorroborationWindow`; otherwise it
///   is rejected as `handOverLens`.
/// - Luma without hinge: the collapse from lit to dark must take at most `lumaCollapseMaxDuration`.
///   A stream that stops while dropping fast counts too (unless `lumaStallCountsAlone` is false).
///
/// After a smash both paths disarm: the hinge re-arms at an open angle, luma when the frame is lit again.
/// Samples older than the newest of their kind are ignored.
///
/// Call `advance(to:)` once per frame after feeding samples, so timeouts (stall, corroboration window)
/// are evaluated even when no samples arrive.
public struct SmashDetector: Sendable, Equatable {
    public var tunables: FlyTunables
    /// Whether a hinge API is available on this device. Decides how luma evidence is treated.
    public var hingeAvailable: Bool
    public private(set) var lastEvent: SmashEvent?
    /// Rejections since the last `drainRejections()` (at most 32 kept).
    public private(set) var rejections: [SmashRejection]

    private struct LumaCandidate: Sendable, Equatable {
        var evidenceTime: Double
        var createdAt: Double
        var motionStartTime: Double
        var stalled: Bool
    }

    private struct HingeRun: Sendable, Equatable {
        var startAngle: Double
        var motionStartTime: Double
    }

    private var hinge: [HingeSample]
    private var luma: [LumaSample]
    private var hingeArmed: Bool
    private var lumaArmed: Bool
    private var pending: LumaCandidate?
    private var handledStallTime: Double?

    private static let maxHingeSamples = 1024
    private static let maxLumaSamples = 1024
    private static let maxRejections = 32

    public init(tunables: FlyTunables = FlyTunables(), hingeAvailable: Bool) {
        self.tunables = tunables
        self.hingeAvailable = hingeAvailable
        self.lastEvent = nil
        self.rejections = []
        self.hinge = []
        self.luma = []
        self.hingeArmed = false
        self.lumaArmed = false
        self.pending = nil
        self.handledStallTime = nil
    }

    /// True once the hinge has been seen open since the last smash.
    public var isHingeArmed: Bool { return hingeArmed }
    /// True once the camera has been seen lit since the last smash.
    public var isLumaArmed: Bool { return lumaArmed }
    /// True while darkness is waiting for the hinge to confirm it.
    public var isAwaitingHinge: Bool { return pending != nil }

    // MARK: Inputs

    /// Feeds one hinge sample. Returns a smash if this sample completes one.
    @discardableResult
    public mutating func addHinge(_ sample: HingeSample) -> SmashEvent? {
        if !sample.angle.isFinite || !sample.time.isFinite { return nil }
        if let last = hinge.last, sample.time < last.time { return nil }
        hinge.append(sample)
        // Keep enough history for the slowest close that counts, and always the last few samples
        // (sparse hinge APIs may only report on change).
        let keepAfter = sample.time - (tunables.closeMaxDuration + 1.0)
        var dropCount = 0
        while dropCount < hinge.count - 4 && hinge[dropCount].time < keepAfter {
            dropCount += 1
        }
        if hinge.count - dropCount > SmashDetector.maxHingeSamples {
            dropCount = hinge.count - SmashDetector.maxHingeSamples
        }
        if dropCount > 0 {
            hinge.removeFirst(dropCount)
        }

        let closed = isClosed(sample)
        if !closed && sample.angle >= tunables.hingeArmAngle {
            hingeArmed = true
        }

        if let candidate = pending {
            if sample.time - candidate.createdAt <= tunables.hingeCorroborationWindow && hingeCorroborates(candidate) {
                pending = nil
                return emitCombined(candidate, at: sample.time)
            }
            expirePending(now: sample.time)
        }

        if closed && hingeArmed {
            hingeArmed = false
            return evaluateHingeClose(sample)
        }
        return nil
    }

    /// Feeds one brightness sample. Returns a smash if this sample completes one.
    @discardableResult
    public mutating func addLuma(_ sample: LumaSample) -> SmashEvent? {
        if !sample.mean.isFinite || !sample.time.isFinite { return nil }
        if let last = luma.last, sample.time < last.time { return nil }
        luma.append(sample)
        let keepAfter = sample.time - (tunables.lumaLookback + 1.0)
        var drop = 0
        while drop < luma.count - 2 && luma[drop].time < keepAfter {
            drop += 1
        }
        if luma.count - drop > SmashDetector.maxLumaSamples {
            drop = luma.count - SmashDetector.maxLumaSamples
        }
        if drop > 0 {
            luma.removeFirst(drop)
        }

        expirePending(now: sample.time)

        if sample.mean >= tunables.litThreshold {
            lumaArmed = true
        }
        if sample.mean <= tunables.darkeningThreshold && lumaArmed && pending == nil {
            return evaluateLumaCollapse(endIndex: luma.count - 1, stalled: false, now: sample.time)
        }
        return nil
    }

    /// Moves the detector's clock to `time` (call once per frame). Expires a pending hand-over-lens
    /// check and notices a luma stream that stopped while dropping.
    @discardableResult
    public mutating func advance(to time: Double) -> SmashEvent? {
        if !time.isFinite { return nil }
        expirePending(now: time)
        return checkStall(now: time)
    }

    /// Debug button / stand-in. Ignores arming but respects the debounce. Motion start = `time`.
    @discardableResult
    public mutating func manualSmash(at time: Double) -> SmashEvent? {
        return emit(SmashEvent(time: time, motionStartTime: time, source: .manual))
    }

    /// Returns and clears the recorded rejections.
    public mutating func drainRejections() -> [SmashRejection] {
        let r = rejections
        rejections = []
        return r
    }

    /// Forgets all samples, arming and the last event.
    public mutating func reset() {
        lastEvent = nil
        rejections = []
        hinge = []
        luma = []
        hingeArmed = false
        lumaArmed = false
        pending = nil
        handledStallTime = nil
    }

    // MARK: Hinge path

    private func isClosed(_ s: HingeSample) -> Bool {
        if let st = s.status, st == .closed { return true }
        // A status mapped from the raw integer is a guess until P5: it may only shut a hinge whose
        // angle is below the arming angle, so a wrong mapping can never make an open hinge look shut.
        if s.status == nil, s.angle < tunables.hingeArmAngle,
           let mapped = tunables.hingeStatusMapping.status(forRaw: s.statusRaw), mapped == .closed {
            return true
        }
        return s.angle <= tunables.hingeClosedAngle
    }

    private mutating func evaluateHingeClose(_ sample: HingeSample) -> SmashEvent? {
        guard let run = hingeRun() else {
            reject(.closeTooSmall, at: sample.time)
            return nil
        }
        let totalDrop = run.startAngle - sample.angle
        if totalDrop < tunables.hingeMinCloseDrop {
            reject(.closeTooSmall, at: sample.time)
            return nil
        }
        let duration = sample.time - run.motionStartTime
        if duration > tunables.closeMaxDuration {
            reject(.closeTooSlow, at: sample.time)
            return nil
        }
        if duration > 0 && totalDrop / duration < tunables.smashMinAngularSpeed {
            reject(.closeTooSlow, at: sample.time)
            return nil
        }
        return emit(SmashEvent(time: sample.time, motionStartTime: run.motionStartTime, source: .hinge))
    }

    /// The strictly falling run of hinge samples ending at the newest one (a trailing plateau of
    /// equal angles, such as a late `.closed` status, is skipped). Nil if there is no fall.
    private func hingeRun() -> HingeRun? {
        var n = hinge.count
        while n >= 2 && abs(hinge[n - 2].angle - hinge[n - 1].angle) < 1e-9 {
            n -= 1
        }
        if n < 2 { return nil }
        var i = n - 1
        while i > 0 && hinge[i - 1].angle > hinge[i].angle {
            i -= 1
        }
        if i == n - 1 { return nil }
        let startAngle = hinge[i].angle
        // The close begins in the first segment that is fast enough or big enough (skips drift and jitter).
        var k = i
        while k < n - 1 {
            let a = hinge[k]
            let b = hinge[k + 1]
            let drop = a.angle - b.angle
            let dt = b.time - a.time
            let fastEnough = dt <= 0 || drop / dt >= tunables.hingeStillSpeed
            if fastEnough || drop >= tunables.hingeSegmentMinDrop {
                let nominal = max(tunables.smashNominalAngularSpeed, 0.001)
                let estimate = b.time - drop / nominal
                return HingeRun(startAngle: startAngle, motionStartTime: max(a.time, estimate))
            }
            k += 1
        }
        return HingeRun(startAngle: startAngle, motionStartTime: hinge[i].time)
    }

    /// Has the hinge fallen enough since the luma candidate's motion start (or is it shut)?
    private func hingeCorroborates(_ candidate: LumaCandidate) -> Bool {
        guard let newest = hinge.last else { return false }
        if isClosed(newest) { return true }
        var reference = hinge[0]
        for h in hinge where h.time <= candidate.motionStartTime {
            reference = h
        }
        return reference.angle - newest.angle >= tunables.hingeCorroborationDrop
    }

    private mutating func emitCombined(_ candidate: LumaCandidate, at time: Double) -> SmashEvent? {
        var start = candidate.motionStartTime
        if let run = hingeRun() {
            start = min(start, run.motionStartTime)
        }
        return emit(SmashEvent(time: time, motionStartTime: start, source: .hingeAndLuma, lumaStalled: candidate.stalled))
    }

    // MARK: Luma path

    private mutating func expirePending(now: Double) {
        guard let candidate = pending else { return }
        if now - candidate.createdAt > tunables.hingeCorroborationWindow {
            pending = nil
            lumaArmed = false
            reject(.handOverLens, at: now)
        }
    }

    private mutating func checkStall(now: Double) -> SmashEvent? {
        if !lumaArmed || pending != nil || luma.count < 2 { return nil }
        let last = luma[luma.count - 1]
        let previous = luma[luma.count - 2]
        if now - last.time <= tunables.lumaStallTimeout { return nil }
        if let handled = handledStallTime, handled >= last.time { return nil }
        handledStallTime = last.time
        if !(last.mean < previous.mean) { return nil }
        let baseline = lumaBaseline(before: luma.count - 1)
        if baseline < tunables.litThreshold { return nil }
        if last.mean > baseline * tunables.lumaStallDropRatio { return nil }
        return evaluateLumaCollapse(endIndex: luma.count - 1, stalled: true, now: now)
    }

    /// Brightest sample within `lumaLookback` before `endIndex` (exclusive). 0 if none.
    private func lumaBaseline(before endIndex: Int) -> Double {
        if endIndex <= 0 || endIndex >= luma.count { return 0 }
        let windowStart = luma[endIndex].time - tunables.lumaLookback
        var baseline = 0.0
        var j = 0
        while j < endIndex {
            if luma[j].time >= windowStart && luma[j].mean > baseline {
                baseline = luma[j].mean
            }
            j += 1
        }
        return baseline
    }

    private mutating func evaluateLumaCollapse(endIndex: Int, stalled: Bool, now: Double) -> SmashEvent? {
        let end = luma[endIndex]
        let baseline = lumaBaseline(before: endIndex)
        if baseline < tunables.litThreshold {
            lumaArmed = false
            if !hingeAvailable {
                reject(.collapseTooSlow, at: now)
            }
            return nil
        }
        var startTime = end.time
        var j = endIndex - 1
        while j >= 0 {
            if luma[j].mean >= baseline * tunables.lumaStartFraction {
                startTime = luma[j].time
                break
            }
            j -= 1
        }
        let collapseDuration = end.time - startTime
        let candidate = LumaCandidate(evidenceTime: end.time,
                                      createdAt: now,
                                      motionStartTime: startTime - tunables.lumaMotionLead,
                                      stalled: stalled)
        if hingeAvailable {
            if hingeCorroborates(candidate) {
                return emitCombined(candidate, at: now)
            }
            pending = candidate
            return nil
        }
        lumaArmed = false
        if collapseDuration > tunables.lumaCollapseMaxDuration {
            reject(.collapseTooSlow, at: now)
            return nil
        }
        if stalled && !tunables.lumaStallCountsAlone {
            reject(.stallOnly, at: now)
            return nil
        }
        return emit(SmashEvent(time: now, motionStartTime: candidate.motionStartTime, source: .luma, lumaStalled: stalled))
    }

    // MARK: Output

    private mutating func emit(_ event: SmashEvent) -> SmashEvent? {
        if let last = lastEvent, event.time - last.time < tunables.smashDebounce {
            reject(.debounced, at: event.time)
            return nil
        }
        lastEvent = event
        hingeArmed = false
        lumaArmed = false
        pending = nil
        return event
    }

    private mutating func reject(_ reason: SmashRejectReason, at time: Double) {
        rejections.append(SmashRejection(time: time, reason: reason))
        if rejections.count > SmashDetector.maxRejections {
            rejections.removeFirst(rejections.count - SmashDetector.maxRejections)
        }
    }
}
