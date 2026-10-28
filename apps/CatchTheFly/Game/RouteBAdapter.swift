import Foundation
import CoreGraphics

/// The part of the upright camera image that the aspect-fill preview shows, in normalised image
/// coordinates (origin top-left). FlyCore's screen space is exactly this rectangle.
struct DisplayCrop: Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = DisplayCrop(x: 0, y: 0, width: 1, height: 1)

    static func aspectFill(imageWidth: Int, imageHeight: Int, viewSize: CGSize) -> DisplayCrop {
        let iw = Double(imageWidth)
        let ih = Double(imageHeight)
        let vw = Double(viewSize.width)
        let vh = Double(viewSize.height)
        guard iw > 0, ih > 0, vw > 0, vh > 0 else { return .full }
        let imageAspect = iw / ih
        let viewAspect = vw / vh
        if viewAspect > imageAspect {
            // Image scaled to the view's width; top and bottom cut off.
            let f = imageAspect / viewAspect
            return DisplayCrop(x: 0, y: (1 - f) / 2, width: 1, height: f)
        } else {
            let f = viewAspect / imageAspect
            return DisplayCrop(x: (1 - f) / 2, y: 0, width: f, height: 1)
        }
    }

    /// Image point (top-left origin) to FlyCore screen point.
    func toScreen(x u: Double, y v: Double) -> FlyScreenPoint {
        return FlyScreenPoint(x: (u - x) / width, y: (v - y) / height)
    }
}

/// Thin conversions from route B platform data to FlyCore inputs. No game rules here.
enum RouteBAdapter {
    /// FlyCamera at the origin (the player is assumed to stand still), turned by CoreMotion,
    /// with fields of view for the displayed (cropped) picture.
    static func camera(geometry: CameraGeometry?, crop: DisplayCrop, pose: PoseSample?) -> FlyCamera {
        guard let g = geometry else {
            return FlyCamera(horizontalFOV: 1.0, verticalFOV: 0.75)
        }
        let hFOV = 2 * atan(tan(g.horizontalFOV / 2) * crop.width)
        let vFOV = 2 * atan(tan(g.verticalFOV / 2) * crop.height)
        let forward: Vec3
        let right: Vec3
        let up: Vec3
        if let p = pose {
            forward = p.toWorld(g.forwardInDevice).normalised()
            right = p.toWorld(g.rightInDevice).normalised()
            up = p.toWorld(g.upInDevice).normalised()
        } else {
            forward = g.forwardInDevice
            right = g.rightInDevice
            up = g.upInDevice
        }
        return FlyCamera(position: Vec3.zero, forward: forward, right: right, up: up,
                         horizontalFOV: hFOV, verticalFOV: vFOV)
    }

    /// Unit direction from the camera through a screen point (inverse of FlyCamera.project).
    static func direction(through p: FlyScreenPoint, camera: FlyCamera) -> Vec3 {
        let tx = tan(camera.horizontalFOV / 2) * (2 * p.x - 1)
        let ty = tan(camera.verticalFOV / 2) * (1 - 2 * p.y)
        return (camera.forward + camera.right * tx + camera.up * ty).normalised()
    }

    /// FlyCore's view of one tracked patch (id, scale ratio, confidence).
    static func reading(_ p: PatchObservation) -> PatchScaleReading {
        return PatchScaleReading(id: p.id, ratio: p.scaleRatio, confidence: p.confidence)
    }

    /// Every patch in a report, for `PatchReferenceBook.update(_:)`.
    static func readings(from report: TrackerReport) -> [PatchScaleReading] {
        return report.patches.map { reading($0) }
    }

    /// One LandingSpot per visible patch: on the ray through the patch, at its distance from FlyCore's
    /// `PatchReferenceBook`, facing the camera. A landed fly then projects exactly onto its patch.
    static func spots(from report: TrackerReport, crop: DisplayCrop, camera: FlyCamera, references: PatchReferenceBook) -> [LandingSpot] {
        var out: [LandingSpot] = []
        for p in report.patches {
            let s = crop.toScreen(x: p.centreX, y: p.centreY)
            guard s.isOnScreen else { continue }
            guard let d = references.distance(for: reading(p)), d.isFinite, d > 0 else { continue }
            let dir = direction(through: s, camera: camera)
            out.append(LandingSpot(id: p.id, position: camera.position + dir * d, normal: -dir,
                                   quality: min(1, max(0, p.quality * p.confidence))))
        }
        return out
    }

    /// The patch-scale reading for the patch the fly is on (or heading to), with its confidence and
    /// the camera frame's timestamp (FlyCore ignores a reading it has already counted).
    static func measurement(forSpot spotID: Int?, report: TrackerReport, references: PatchReferenceBook)
        -> (measurement: DistanceMeasurement, confidence: Double, measuredAt: Double)? {
        guard let id = spotID, let p = report.patches.first(where: { $0.id == id }),
              let m = references.measurement(for: reading(p)) else { return nil }
        return (m, p.confidence, report.time)
    }

    /// The hit region as a normalised rectangle (for drawing only; FlyCore does the judging).
    static func hitRect(edge: HingeEdge, tunables: FlyTunables) -> CGRect {
        let w = tunables.hitRegionWidth
        let m = tunables.hitBlockedMargin
        switch edge {
        case .left: return CGRect(x: m, y: 0, width: max(0, w - m), height: 1)
        case .right: return CGRect(x: 1 - w, y: 0, width: max(0, w - m), height: 1)
        case .top: return CGRect(x: 0, y: m, width: 1, height: max(0, w - m))
        case .bottom: return CGRect(x: 0, y: 1 - w, width: 1, height: max(0, w - m))
        case .centre: return CGRect(x: 0.5 - w / 2, y: 0.5 - w / 2, width: w, height: w)
        }
    }
}
