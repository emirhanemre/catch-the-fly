import Foundation

/// Where best times are kept. The app implements this (for example over UserDefaults);
/// FlyCore never touches storage itself.
public protocol BestTimeStore {
    /// The saved best round time in seconds, or nil if none.
    func loadBestTime() -> Double?
    /// Saves a new best round time in seconds.
    func saveBestTime(_ seconds: Double)
}

public enum FlyRoundPhase: String, Sendable, Equatable, CaseIterable {
    /// No round running (before the first `start()`, or after `cancel()`).
    case idle
    case playing
    /// All flies caught; `lastRoundTime` holds the result.
    case finished
}

/// What a catch did to the round.
public struct FlyRoundProgress: Sendable, Equatable {
    /// Flies caught so far this round (after this catch).
    public var fliesCaught: Int
    /// Seconds since the previous catch (or the round start). 0 if the catch was ignored.
    public var flyTime: Double
    /// True if this catch completed the round.
    public var roundFinished: Bool
    /// The round time, if the round finished.
    public var roundTime: Double?
    /// True if the round finished faster than the previous best (or there was none).
    public var isNewBest: Bool
    /// False if no round was playing, so nothing was counted.
    public var counted: Bool

    public init(fliesCaught: Int, flyTime: Double, roundFinished: Bool, roundTime: Double?, isNewBest: Bool, counted: Bool) {
        self.fliesCaught = fliesCaught
        self.flyTime = flyTime
        self.roundFinished = roundFinished
        self.roundTime = roundTime
        self.isNewBest = isNewBest
        self.counted = counted
    }
}

/// A round of `fliesPerRound` flies against the clock. Time only runs while playing.
public struct FlyRound: Sendable, Equatable {
    public let fliesPerRound: Int
    public private(set) var phase: FlyRoundPhase
    public private(set) var fliesCaught: Int
    /// Seconds played this round.
    public private(set) var elapsed: Double
    /// Time taken for each fly caught this round (s).
    public private(set) var flyTimes: [Double]
    /// Best completed round time (s), nil if none.
    public private(set) var bestTime: Double?
    /// The time of the most recently finished round (s).
    public private(set) var lastRoundTime: Double?

    private var lastCatchElapsed: Double

    /// `fliesPerRound` below 1 is treated as 1. A non-finite or non-positive `bestTime` is ignored.
    public init(fliesPerRound: Int = 3, bestTime: Double? = nil) {
        self.fliesPerRound = max(1, fliesPerRound)
        self.phase = .idle
        self.fliesCaught = 0
        self.elapsed = 0
        self.flyTimes = []
        self.bestTime = FlyRound.validTime(bestTime)
        self.lastRoundTime = nil
        self.lastCatchElapsed = 0
    }

    /// Loads the best time from `store`.
    public init<S: BestTimeStore>(fliesPerRound: Int = 3, store: S) {
        self.init(fliesPerRound: fliesPerRound, bestTime: store.loadBestTime())
    }

    public var fliesRemaining: Int {
        return max(0, fliesPerRound - fliesCaught)
    }

    /// Starts (or restarts) a round from zero.
    public mutating func start() {
        phase = .playing
        fliesCaught = 0
        elapsed = 0
        flyTimes = []
        lastCatchElapsed = 0
    }

    /// Abandons the round without a result.
    public mutating func cancel() {
        phase = .idle
    }

    /// Advances the clock while playing. Negative or non-finite `dt` is ignored.
    public mutating func tick(dt: Double) {
        if phase != .playing || !dt.isFinite || dt <= 0 { return }
        elapsed += dt
    }

    /// Counts a caught fly. Ignored (with `counted == false`) unless playing.
    @discardableResult
    public mutating func recordCatch() -> FlyRoundProgress {
        if phase != .playing {
            return FlyRoundProgress(fliesCaught: fliesCaught, flyTime: 0, roundFinished: false, roundTime: nil, isNewBest: false, counted: false)
        }
        fliesCaught += 1
        let flyTime = elapsed - lastCatchElapsed
        lastCatchElapsed = elapsed
        flyTimes.append(flyTime)
        if fliesCaught < fliesPerRound {
            return FlyRoundProgress(fliesCaught: fliesCaught, flyTime: flyTime, roundFinished: false, roundTime: nil, isNewBest: false, counted: true)
        }
        phase = .finished
        let roundTime = elapsed
        lastRoundTime = roundTime
        var isNewBest = true
        if let best = bestTime, best <= roundTime {
            isNewBest = false
        }
        if isNewBest {
            bestTime = roundTime
        }
        return FlyRoundProgress(fliesCaught: fliesCaught, flyTime: flyTime, roundFinished: true, roundTime: roundTime, isNewBest: isNewBest, counted: true)
    }

    /// As `recordCatch()`, and saves the time to `store` when it is a new best.
    @discardableResult
    public mutating func recordCatch<S: BestTimeStore>(savingTo store: S) -> FlyRoundProgress {
        let progress = recordCatch()
        if progress.isNewBest, let t = progress.roundTime {
            store.saveBestTime(t)
        }
        return progress
    }

    private static func validTime(_ t: Double?) -> Double? {
        guard let v = t, v.isFinite, v > 0 else { return nil }
        return v
    }
}
