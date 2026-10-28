import XCTest
@testable import FlyCore

final class PresetTests: XCTestCase {

    func testNewTunableDefaults() {
        let t = FlyTunables()
        XCTAssertEqual(t.patchDefaultReferenceDistance, 1.0)
        XCTAssertEqual(t.patchReferenceMinimumPeers, 1)
        XCTAssertEqual(t.patchReferenceMinimumPeerConfidence, 0.3)
        XCTAssertEqual(t.patchReferenceMinimumDistance, 0.2)
        XCTAssertEqual(t.patchReferenceMaximumDistance, 5.0)
        XCTAssertEqual(t.hingeStatusMapping, .declarationOrderGuess)
    }

    func testIPadPrototype() {
        var expected = FlyTunables()
        expected.smashDistance = 0.25
        XCTAssertEqual(FlyTunables.iPadPrototype, expected)
        XCTAssertEqual(FlyPreset.iPadPrototype.tunables, expected)
        XCTAssertEqual(FlyPreset.iPadPrototype.hingeEdge, .centre)
        XCTAssertEqual(FlyPreset.iPadPrototype.name, "iPadPrototype")
    }

    func testDuoPostures() {
        XCTAssertEqual(FlyTunables.duoPostureA, FlyTunables())
        XCTAssertEqual(FlyPreset.duoPostureA.hingeEdge, .right)
        var b = FlyTunables()
        b.closeMaxDuration = 4.0
        b.smashDistance = 0.15
        b.hitRegionWidth = 0.6
        XCTAssertEqual(FlyTunables.duoPostureB, b)
        XCTAssertEqual(FlyPreset.duoPostureB.hingeEdge, .centre)
        XCTAssertEqual(FlyPreset.all.map { $0.name }, ["iPadPrototype", "duoPostureA", "duoPostureB"])
        let custom = FlyPreset(name: "x", tunables: b, hingeEdge: .left)
        XCTAssertEqual(custom.tunables, b)
        XCTAssertEqual(custom.hingeEdge, .left)
    }

    func testPresetDrivesFlyGame() {
        let p = FlyPreset.iPadPrototype
        let game = FlyGame(tunables: p.tunables, seed: 1, hingeEdge: p.hingeEdge, hingeAvailable: false)
        XCTAssertEqual(game.tunables.smashDistance, 0.25)
        XCTAssertEqual(game.hingeEdge, .centre)
    }
}
