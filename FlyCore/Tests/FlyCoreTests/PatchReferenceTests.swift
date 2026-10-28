import XCTest
@testable import FlyCore

final class PatchReferenceTests: XCTestCase {

    func testMedian() {
        XCTAssertNil(PatchReferencePolicy.median([]))
        XCTAssertEqual(PatchReferencePolicy.median([3, 1, 2]), 2)
        XCTAssertEqual(PatchReferencePolicy.median([4, 1, 3, 2]), 2.5)
    }

    func testSeedDistance() {
        let p = PatchReferencePolicy()
        XCTAssertEqual(p.seedDistance(peerDistances: []), 1.0)
        XCTAssertEqual(p.seedDistance(peerDistances: [0.5, 2.0, 0.7]), 0.7)
        XCTAssertEqual(p.seedDistance(peerDistances: [Double.nan, -1, 0, 0.6]), 0.6, "invalid peers ignored")
        XCTAssertEqual(p.seedDistance(peerDistances: [0.05]), 0.2, "clamped to minimumDistance")
        XCTAssertEqual(p.seedDistance(peerDistances: [9]), 5.0, "clamped to maximumDistance")
        var two = p
        two.minimumPeers = 2
        XCTAssertEqual(two.seedDistance(peerDistances: [0.5]), 1.0, "too few peers: default")
        XCTAssertEqual(two.seedDistance(peerDistances: [0.5, 0.7]), 0.6, accuracy: 1e-12)
        var odd = p
        odd.defaultDistance = 0.1
        XCTAssertEqual(odd.seedDistance(peerDistances: []), 0.2, "the default is clamped too")
    }

    func testPolicyFromTunables() {
        var t = FlyTunables()
        XCTAssertEqual(PatchReferencePolicy(tunables: t), PatchReferencePolicy())
        t.patchDefaultReferenceDistance = 1.5
        t.patchReferenceMinimumPeers = 2
        t.patchReferenceMinimumPeerConfidence = 0.5
        t.patchReferenceMinimumDistance = 0.3
        t.patchReferenceMaximumDistance = 4.0
        XCTAssertEqual(PatchReferencePolicy(tunables: t),
                       PatchReferencePolicy(defaultDistance: 1.5, minimumPeers: 2, minimumPeerConfidence: 0.5,
                                            minimumDistance: 0.3, maximumDistance: 4.0))
    }

    func testFirstPatchGetsDefaultAndLaterPatchesBorrowTheMedian() {
        var book = PatchReferenceBook()
        XCTAssertEqual(book.update([PatchScaleReading(id: 1, ratio: 1.0)]), [1])
        XCTAssertEqual(book.referenceDistance(for: 1), 1.0)
        XCTAssertEqual(book.distance(for: PatchScaleReading(id: 1, ratio: 1.0)), 1.0)

        // The player walks to half the distance; patch 2 appears and borrows patch 1's distance.
        let a = PatchScaleReading(id: 1, ratio: 2.0)
        let b = PatchScaleReading(id: 2, ratio: 1.0)
        XCTAssertEqual(book.update([a, b]), [2])
        XCTAssertEqual(book.referenceDistance(for: 1), 1.0, "a known patch keeps its reference")
        XCTAssertEqual(book.referenceDistance(for: 2), 0.5)
        XCTAssertEqual(book.distance(for: b), 0.5)
        XCTAssertEqual(book.measurement(for: b), .patchScale(ratio: 1.0, referenceDistance: 0.5))
        XCTAssertEqual(book.measurement(for: a)?.metres ?? 0, 0.5, accuracy: 1e-12)
    }

    func testNewPatchFirstSeenAfterItsSeedFrameMatchesPeersNow() {
        var book = PatchReferenceBook()
        book.update([PatchScaleReading(id: 1, ratio: 1.0)])
        // Patch 2 already grew by 25 % before the game saw it: its distance now equals the peers' now.
        book.update([PatchScaleReading(id: 1, ratio: 1.25), PatchScaleReading(id: 2, ratio: 1.25)])
        XCTAssertEqual(book.referenceDistance(for: 2) ?? 0, 1.0, accuracy: 1e-12)
        XCTAssertEqual(book.distance(for: PatchScaleReading(id: 2, ratio: 1.25)) ?? 0, 0.8, accuracy: 1e-12)
    }

    func testPatchesSeededTogetherDoNotBorrowFromEachOther() {
        var book = PatchReferenceBook()
        XCTAssertEqual(book.update([PatchScaleReading(id: 5, ratio: 1), PatchScaleReading(id: 6, ratio: 1)]), [5, 6])
        XCTAssertEqual(book.referenceDistance(for: 5), 1.0)
        XCTAssertEqual(book.referenceDistance(for: 6), 1.0)
    }

    func testLowConfidencePeersAreNotBorrowedFrom() {
        var book = PatchReferenceBook()
        book.update([PatchScaleReading(id: 1, ratio: 1)])
        book.update([PatchScaleReading(id: 1, ratio: 2, confidence: 0.1), PatchScaleReading(id: 2, ratio: 1)])
        XCTAssertEqual(book.referenceDistance(for: 2), 1.0)
    }

    func testLostPatchesAreForgottenAndReusedIdsAreNew() {
        var book = PatchReferenceBook()
        book.update([PatchScaleReading(id: 1, ratio: 1)])
        book.update([PatchScaleReading(id: 1, ratio: 2), PatchScaleReading(id: 2, ratio: 1)])
        book.update([PatchScaleReading(id: 2, ratio: 1)])
        XCTAssertEqual(Array(book.references.keys), [2])
        XCTAssertNil(book.distance(for: PatchScaleReading(id: 1, ratio: 2)))
        XCTAssertEqual(book.update([PatchScaleReading(id: 2, ratio: 1), PatchScaleReading(id: 1, ratio: 1)]), [1])
        XCTAssertEqual(book.referenceDistance(for: 1), 0.5)
    }

    func testInvalidRatiosAndDuplicates() {
        var book = PatchReferenceBook()
        XCTAssertEqual(book.update([PatchScaleReading(id: 1, ratio: 0), PatchScaleReading(id: 2, ratio: Double.nan)]), [])
        XCTAssertTrue(book.references.isEmpty)
        book.update([PatchScaleReading(id: 1, ratio: 1)])
        // Known patch with a bad ratio this frame: kept, but not a peer and no distance.
        XCTAssertEqual(book.update([PatchScaleReading(id: 1, ratio: -1), PatchScaleReading(id: 3, ratio: 1)]), [3])
        XCTAssertEqual(book.referenceDistance(for: 1), 1.0)
        XCTAssertNil(book.distance(for: PatchScaleReading(id: 1, ratio: -1)))
        XCTAssertNil(book.measurement(for: PatchScaleReading(id: 1, ratio: -1)))
        XCTAssertNil(book.measurement(for: PatchScaleReading(id: 9, ratio: 1)))
        // A repeated id is handled once.
        var dup = PatchReferenceBook()
        XCTAssertEqual(dup.update([PatchScaleReading(id: 4, ratio: 1), PatchScaleReading(id: 4, ratio: 2)]), [4])
        XCTAssertEqual(dup.referenceDistance(for: 4), 1.0)
    }

    func testResetAndPolicyChange() {
        var book = PatchReferenceBook(policy: PatchReferencePolicy(defaultDistance: 2.0))
        book.update([PatchScaleReading(id: 1, ratio: 1)])
        XCTAssertEqual(book.referenceDistance(for: 1), 2.0)
        book.reset()
        XCTAssertTrue(book.references.isEmpty)
        book.policy.defaultDistance = 0.8
        book.update([PatchScaleReading(id: 1, ratio: 1)])
        XCTAssertEqual(book.referenceDistance(for: 1), 0.8)
    }
}
