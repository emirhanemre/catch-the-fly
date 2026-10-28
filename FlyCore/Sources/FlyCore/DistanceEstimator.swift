import Foundation

/// One raw distance reading, from whichever tracking route is running.
public enum DistanceMeasurement: Sendable, Equatable {
    /// Routes A1/A2/P-B: a world-space distance from the camera to the fly, in metres.
    case world(metres: Double)
    /// Route B: the tracked patch's current size divided by its size when it was `referenceDistance`
    /// metres away. Pinhole model: distance = referenceDistance / ratio.
    case patchScale(ratio: Double, referenceDistance: Double)

    /// The distance this measurement implies (m), or nil if it is invalid (non-finite, zero or negative).
    public var metres: Double? {
        switch self {
        case .world(let m):
            if m.isFinite && m > 0 { return m }
            return nil
        case .patchScale(let ratio, let referenceDistance):
            if ratio.isFinite && ratio > 0 && referenceDistance.isFinite && referenceDistance > 0 {
                return referenceDistance / ratio
            }
            return nil
        }
    }

    fileprivate var kindCode: Int {
        switch self {
        case .world: return 0
        case .patchScale: return 1
        }
    }
}

/// A smoothed distance with a confidence and an approach rate.
public struct DistanceEstimate: Sendable, Equatable {
    /// Smoothed distance (m), nil until the first valid measurement.
    public var metres: Double?
    /// 0...1. The source confidence of the last measurement, fading to 0 over `staleTime` without one.
    public var confidence: Double
    /// Smoothed closing speed (m/s, positive = getting closer).
    public var approachRate: Double
    /// Time of the update that produced this estimate (s).
    public var time: Double

    public init(metres: Double?, confidence: Double, approachRate: Double, time: Double) {
        self.metres = metres
        self.confidence = confidence
        self.approachRate = approachRate
        self.time = time
    }

    public static let unknown = DistanceEstimate(metres: nil, confidence: 0, approachRate: 0, time: 0)
}

/// Route-agnostic distance smoother.
///
/// Feed it once per frame with `update(_:sourceConfidence:time:)`, passing nil when there is no reading,
/// or with `update(_:measuredAt:sourceConfidence:time:)` when readings carry their own timestamp
/// (a stale reading, one not newer than the last counted, is then treated as none).
/// A reading that implies a change faster than `jumpRate`, a switch between measurement kinds, or a
/// gap longer than `staleTime` re-seeds the estimate (distance snaps, approach rate goes to 0), so a
/// tracker glitch or patch switch never looks like a lunge.
public struct DistanceEstimator: Sendable, Equatable {
    public var smoothingTime: Double
    public var rateSmoothingTime: Double
    public var staleTime: Double
    public var jumpRate: Double
    public var minimumDistance: Double
    public var maximumDistance: Double

    public private(set) var estimate: DistanceEstimate

    private var lastMeasurementTime: Double?
    private var lastUpdateTime: Double?
    private var lastKind: Int?
    private var lastRaw: Double?
    private var lastSourceConfidence: Double
    private var lastMeasuredRate: Double

    public init(smoothingTime: Double = 0.12,
                rateSmoothingTime: Double = 0.25,
                staleTime: Double = 0.5,
                jumpRate: Double = 4.0,
                minimumDistance: Double = 0.02,
                maximumDistance: Double = 20.0) {
        self.smoothingTime = smoothingTime
        self.rateSmoothingTime = rateSmoothingTime
        self.staleTime = staleTime
        self.jumpRate = jumpRate
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
        self.estimate = DistanceEstimate.unknown
        self.lastMeasurementTime = nil
        self.lastUpdateTime = nil
        self.lastKind = nil
        self.lastRaw = nil
        self.lastSourceConfidence = 0
        self.lastMeasuredRate = 0
    }

    public init(tunables: FlyTunables) {
        self.init(smoothingTime: tunables.distanceSmoothingTime,
                  rateSmoothingTime: tunables.approachRateSmoothingTime,
                  staleTime: tunables.distanceStaleTime,
                  jumpRate: tunables.distanceJumpRate,
                  minimumDistance: tunables.minimumDistance,
                  maximumDistance: tunables.maximumDistance)
    }

    /// Copies the distance settings from `tunables` without losing state.
    public mutating func apply(_ tunables: FlyTunables) {
        smoothingTime = tunables.distanceSmoothingTime
        rateSmoothingTime = tunables.approachRateSmoothingTime
        staleTime = tunables.distanceStaleTime
        jumpRate = tunables.distanceJumpRate
        minimumDistance = tunables.minimumDistance
        maximumDistance = tunables.maximumDistance
    }

    /// Adds a reading (or nil for none this frame) at `time` and returns the new estimate.
    /// `sourceConfidence` (0...1) is how much the route trusts this reading, for example the
    /// Vision tracker's confidence. Updates with a time earlier than the previous one are ignored.
    ///
    /// The reading is taken to have been made at `time`. When readings arrive at a different rate
    /// from the update calls (camera frames versus display ticks), use
    /// `update(_:measuredAt:sourceConfidence:time:)` instead.
    @discardableResult
    public mutating func update(_ measurement: DistanceMeasurement?, sourceConfidence: Double = 1.0, time: Double) -> DistanceEstimate {
        return ingest(measurement, measuredAt: nil, sourceConfidence: sourceConfidence, time: time)
    }

    /// Adds a reading made at `measuredAt` (for example the camera frame's timestamp) and returns the
    /// estimate at `time` (the update's own clock, for example the display tick).
    ///
    /// - A reading whose `measuredAt` is not newer than the last reading counted is stale: it is
    ///   treated exactly like nil (distance held, confidence and rate fading), so the app may pass the
    ///   latest frame's reading on every tick without it being counted twice.
    /// - Smoothing, the jump test and the gap test use the reading times, not the update times.
    /// - `measuredAt` later than `time` is treated as `time`. A non-finite `measuredAt` counts as no reading.
    /// - Confidence and approach rate fade with the reading's age (`time - measuredAt`) over `staleTime`,
    ///   just as they do between readings.
    @discardableResult
    public mutating func update(_ measurement: DistanceMeasurement?, measuredAt: Double, sourceConfidence: Double = 1.0, time: Double) -> DistanceEstimate {
        return ingest(measurement, measuredAt: measuredAt, sourceConfidence: sourceConfidence, time: time)
    }

    private mutating func ingest(_ measurement: DistanceMeasurement?, measuredAt: Double?, sourceConfidence: Double, time: Double) -> DistanceEstimate {
        if !time.isFinite { return estimate }
        if let previousUpdate = lastUpdateTime, time < previousUpdate { return estimate }
        lastUpdateTime = time

        // When the reading was made. Nil `measuredAt` means "now" (the original, per-update behaviour).
        var readingTime = time
        var usable = true
        if let mt = measuredAt {
            if !mt.isFinite {
                usable = false
            } else {
                readingTime = min(mt, time)
                if let previousTime = lastMeasurementTime, readingTime <= previousTime {
                    usable = false   // stale: already counted
                }
            }
        }

        var raw: Double? = nil
        var kind: Int = 0
        if usable, let m = measurement, let metres = m.metres {
            raw = FlyMath.clamp(metres, minimumDistance, max(minimumDistance, maximumDistance))
            kind = m.kindCode
        }

        if let value = raw {
            var newMetres = value
            var newRate = 0.0
            if let previous = estimate.metres, let previousTime = lastMeasurementTime, let previousKind = lastKind {
                let dt = readingTime - previousTime
                if dt <= 0 {
                    // Same timestamp as the last reading: keep the current estimate.
                    newMetres = previous
                    newRate = lastMeasuredRate
                } else {
                    let previousRaw = lastRaw ?? previous
                    let rawRate = (previousRaw - value) / dt
                    let isJump = abs(rawRate) > jumpRate || previousKind != kind || dt > staleTime
                    if !isJump {
                        let alpha = FlyMath.smoothingAlpha(dt: dt, timeConstant: smoothingTime)
                        newMetres = previous + (value - previous) * alpha
                        let instantRate = (previous - newMetres) / dt
                        let beta = FlyMath.smoothingAlpha(dt: dt, timeConstant: rateSmoothingTime)
                        // Continue from the last measured rate, not the faded one shown between readings.
                        newRate = lastMeasuredRate + (instantRate - lastMeasuredRate) * beta
                    }
                }
            }
            let c = FlyMath.clamp(sourceConfidence, 0, 1)
            lastMeasurementTime = readingTime
            lastKind = kind
            lastRaw = value
            lastSourceConfidence = c
            lastMeasuredRate = newRate
            let f = freshness(at: time)
            estimate = DistanceEstimate(metres: newMetres, confidence: c * f, approachRate: newRate * f, time: time)
            return estimate
        }

        // No usable reading: hold the distance, fade confidence and approach rate.
        let f = staleTime > 0 ? freshness(at: time) : 0
        estimate = DistanceEstimate(metres: estimate.metres,
                                    confidence: lastSourceConfidence * f,
                                    approachRate: lastMeasuredRate * f,
                                    time: time)
        return estimate
    }

    /// 1 at (or before) the last reading's time, falling linearly to 0 `staleTime` later; 0 before any reading.
    private func freshness(at time: Double) -> Double {
        guard let previousTime = lastMeasurementTime else { return 0 }
        let age = time - previousTime
        if age <= 0 { return 1 }
        if staleTime <= 0 { return 0 }
        return FlyMath.clamp(1.0 - age / staleTime, 0, 1)
    }

    /// Snaps the distance to the last raw reading and zeroes the approach rate.
    /// Call when the target itself stops moving (FlyGame does this when the fly lands), so the
    /// fly's own flight is not mistaken for the player approaching.
    public mutating func rebase() {
        if let r = lastRaw {
            estimate.metres = r
        }
        estimate.approachRate = 0
        lastMeasuredRate = 0
    }

    /// Forgets everything.
    public mutating func reset() {
        estimate = DistanceEstimate.unknown
        lastMeasurementTime = nil
        lastUpdateTime = nil
        lastKind = nil
        lastRaw = nil
        lastSourceConfidence = 0
        lastMeasuredRate = 0
    }
}
