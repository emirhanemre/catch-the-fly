import Foundation

/// Route B: how far away a newly seeded patch is assumed to be.
///
/// A tracked patch only reports a scale ratio (current size / size when first seen), so its distance is
/// `referenceDistance / ratio` and the reference has to be assumed when the patch is first seen:
/// - with at least `minimumPeers` other patches already tracked (each with confidence at least
///   `minimumPeerConfidence` and a valid distance), the median of their current distances (the mean
///   of the middle two for an even count), so a patch seeded after the player walked closer doesn't
///   jump back to the default;
/// - otherwise `defaultDistance` (the player is asked to start about 1 m away).
/// The result is clamped to `minimumDistance...maximumDistance`.
public struct PatchReferencePolicy: Sendable, Equatable {
    public var defaultDistance: Double
    public var minimumPeers: Int
    public var minimumPeerConfidence: Double
    public var minimumDistance: Double
    public var maximumDistance: Double

    public init(defaultDistance: Double = 1.0,
                minimumPeers: Int = 1,
                minimumPeerConfidence: Double = 0.3,
                minimumDistance: Double = 0.2,
                maximumDistance: Double = 5.0) {
        self.defaultDistance = defaultDistance
        self.minimumPeers = minimumPeers
        self.minimumPeerConfidence = minimumPeerConfidence
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
    }

    /// Uses the `patch…` tunables.
    public init(tunables: FlyTunables) {
        self.init(defaultDistance: tunables.patchDefaultReferenceDistance,
                  minimumPeers: tunables.patchReferenceMinimumPeers,
                  minimumPeerConfidence: tunables.patchReferenceMinimumPeerConfidence,
                  minimumDistance: tunables.patchReferenceMinimumDistance,
                  maximumDistance: tunables.patchReferenceMaximumDistance)
    }

    /// The distance (m) to assume for a new patch, given its peers' current distances (already filtered
    /// for confidence). Non-finite and non-positive peer distances are ignored.
    public func seedDistance(peerDistances: [Double]) -> Double {
        let valid = peerDistances.filter { $0.isFinite && $0 > 0 }
        var d = defaultDistance
        if valid.count >= max(1, minimumPeers), let m = PatchReferencePolicy.median(valid) {
            d = m
        }
        if !d.isFinite || d <= 0 { d = 1.0 }
        return FlyMath.clamp(d, minimumDistance, max(minimumDistance, maximumDistance))
    }

    /// The median (mean of the middle two for an even count), nil for an empty list.
    public static func median(_ values: [Double]) -> Double? {
        if values.isEmpty { return nil }
        let s = values.sorted()
        let n = s.count
        if n % 2 == 1 { return s[n / 2] }
        return (s[n / 2 - 1] + s[n / 2]) * 0.5
    }
}

/// One tracked patch this frame, as route B's tracker reports it.
public struct PatchScaleReading: Sendable, Equatable {
    /// The tracker's patch id (stable while tracked).
    public var id: Int
    /// Current size / size when the tracker seeded the patch (above 1 = closer).
    public var ratio: Double
    /// Tracking confidence, 0...1.
    public var confidence: Double

    public init(id: Int, ratio: Double, confidence: Double = 1.0) {
        self.id = id
        self.ratio = ratio
        self.confidence = confidence
    }

    var isValid: Bool { return ratio.isFinite && ratio > 0 }
}

/// Route B: remembers each tracked patch's reference distance, assigned by `policy` when the patch is
/// first seen. Call `update(_:)` with every new tracker report; then `distance(for:)` gives
/// `reference / ratio` and `measurement(for:)` the `DistanceMeasurement.patchScale` to hand to FlyGame.
public struct PatchReferenceBook: Sendable, Equatable {
    public var policy: PatchReferencePolicy
    /// Reference distance (m) per patch id: the patch's distance when its ratio was 1.
    public private(set) var references: [Int: Double]

    public init(policy: PatchReferencePolicy = PatchReferencePolicy()) {
        self.policy = policy
        self.references = [:]
    }

    /// Takes one report's patches and returns the ids that were new (seeded now), in input order.
    ///
    /// - Ids missing from `readings` are forgotten (tracking lost; a reused id later counts as new).
    /// - A new id with a valid ratio gets `policy.seedDistance(peers) * ratio` as its reference, so its
    ///   current distance equals the peers' median. Peers are the readings whose id already had a
    ///   reference before this call, with a valid ratio and confidence at least
    ///   `policy.minimumPeerConfidence`. Patches new in the same call never borrow from each other.
    /// - A new id with an invalid ratio (non-finite or <= 0) is not seeded yet; a known id with an
    ///   invalid ratio keeps its reference. A repeated id is handled once (the first reading).
    @discardableResult
    public mutating func update(_ readings: [PatchScaleReading]) -> [Int] {
        var seen = Set<Int>()
        var unique: [PatchScaleReading] = []
        for r in readings where !seen.contains(r.id) {
            seen.insert(r.id)
            unique.append(r)
        }
        var kept: [Int: Double] = [:]
        var peers: [Double] = []
        for r in unique {
            guard let ref = references[r.id] else { continue }
            kept[r.id] = ref
            if r.isValid && r.confidence >= policy.minimumPeerConfidence {
                peers.append(ref / r.ratio)
            }
        }
        let seedAt = policy.seedDistance(peerDistances: peers)
        var seeded: [Int] = []
        for r in unique where kept[r.id] == nil && r.isValid {
            kept[r.id] = seedAt * r.ratio
            seeded.append(r.id)
        }
        references = kept
        return seeded
    }

    /// The reference distance (m) of a patch, nil if unknown.
    public func referenceDistance(for id: Int) -> Double? {
        return references[id]
    }

    /// The patch's current distance (m), `reference / ratio`; nil if the id is unknown or the ratio invalid.
    public func distance(for reading: PatchScaleReading) -> Double? {
        guard reading.isValid, let ref = references[reading.id] else { return nil }
        return ref / reading.ratio
    }

    /// `.patchScale(ratio:referenceDistance:)` for the patch; nil if the id is unknown or the ratio invalid.
    public func measurement(for reading: PatchScaleReading) -> DistanceMeasurement? {
        guard reading.isValid, let ref = references[reading.id] else { return nil }
        return DistanceMeasurement.patchScale(ratio: reading.ratio, referenceDistance: ref)
    }

    /// Forgets every patch.
    public mutating func reset() {
        references = [:]
    }
}
