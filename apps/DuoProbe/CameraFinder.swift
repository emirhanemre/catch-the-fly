import Foundation
import AVFoundation
import Darwin

struct CameraInfo: Identifiable, Sendable {
    let id: String          // uniqueID
    let name: String
    let position: String
    let typeRaw: String
    let isVirtual: Bool
    let constituents: [String]

    var summary: String {
        var s = "\(name) | id \(id) | position \(position) | type \(typeRaw) | virtual \(isVirtual)"
        if !constituents.isEmpty {
            s += " | constituents: " + constituents.joined(separator: ", ")
        }
        return s
    }
}

struct CameraChoice: Sendable {
    let id: String
    let label: String
    let note: String
    let isDuoInner: Bool
}

/// Finds cameras. Not actor-isolated: AVCaptureDevice discovery is thread-safe.
enum CameraFinder {
    static let innerSymbol = "AVCaptureDeviceTypeBuiltInInnerUltraWideCamera"
    static let outerSymbol = "AVCaptureDeviceTypeBuiltInOuterUltraWideCamera"

    /// Reads an exported NSString constant (e.g. a 27.1 device type) at run time.
    /// Returns nil when this iOS doesn't export the symbol, so we never hand an unknown
    /// device type to DiscoverySession.
    static func exportedString(_ symbol: String) -> String? {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT
        guard let sym = dlsym(defaultHandle, symbol) else { return nil }
        // `sym` is the address of an `NSString * const` variable, so load one (nullable)
        // object pointer from it.
        guard let value = sym.load(as: NSString?.self) else { return nil }
        return value as String
    }

    /// The 27.1 device type for an exported constant, read at run time. Order: the
    /// exported NSString's value; on iOS 27.1+ only, the constant's own name as the raw
    /// value (API_NOTES: plausible, Unverified). Before 27.1 it returns nil, so an
    /// unknown type never reaches DiscoverySession on an older iOS.
    static func runtimeDeviceType(_ symbol: String) -> (type: AVCaptureDevice.DeviceType, source: String)? {
        if let raw = exportedString(symbol) {
            return (AVCaptureDevice.DeviceType(rawValue: raw), "raw value from runtime")
        }
        if #available(iOS 27.1, *) {
            return (AVCaptureDevice.DeviceType(rawValue: symbol), "symbol not found; guessed raw value = name")
        }
        return nil
    }

    /// Native 27.1 device types. Only compiled in the CI build (Xcode 27.1 SDK).
    static func nativeDuoTypes() -> [(String, AVCaptureDevice.DeviceType)] {
        var list: [(String, AVCaptureDevice.DeviceType)] = []
        #if IOS_27_1_SDK
        if #available(iOS 27.1, *) {
            list.append(("builtInInnerUltraWideCamera (native)", .builtInInnerUltraWideCamera))
            list.append(("builtInOuterUltraWideCamera (native)", .builtInOuterUltraWideCamera))
        }
        #endif
        return list
    }

    static func knownTypes() -> [(String, AVCaptureDevice.DeviceType)] {
        var list: [(String, AVCaptureDevice.DeviceType)] = [
            ("builtInWideAngleCamera", .builtInWideAngleCamera),
            ("builtInUltraWideCamera", .builtInUltraWideCamera),
            ("builtInTelephotoCamera", .builtInTelephotoCamera),
            ("builtInDualCamera", .builtInDualCamera),
            ("builtInDualWideCamera", .builtInDualWideCamera),
            ("builtInTripleCamera", .builtInTripleCamera),
            ("builtInTrueDepthCamera", .builtInTrueDepthCamera)
        ]
        if #available(iOS 15.4, *) {
            list.append(("builtInLiDARDepthCamera", .builtInLiDARDepthCamera))
        }
        if #available(iOS 17.0, *) {
            list.append(("external", .external))
        }
        let native = nativeDuoTypes()
        if native.isEmpty {
            if let found = runtimeDeviceType(innerSymbol) {
                list.append(("inner ultra wide (27.1, \(found.source))", found.type))
            }
            if let found = runtimeDeviceType(outerSymbol) {
                list.append(("outer ultra wide (27.1, \(found.source))", found.type))
            }
        } else {
            list.append(contentsOf: native)
        }
        return list
    }

    static func positionName(_ p: AVCaptureDevice.Position) -> String {
        switch p {
        case .front: return "front"
        case .back: return "back"
        case .unspecified: return "unspecified"
        @unknown default: return "other(\(p.rawValue))"
        }
    }

    static func info(_ d: AVCaptureDevice) -> CameraInfo {
        CameraInfo(id: d.uniqueID,
                   name: d.localizedName,
                   position: positionName(d.position),
                   typeRaw: d.deviceType.rawValue,
                   isVirtual: d.isVirtualDevice,
                   constituents: d.constituentDevices.map { "\($0.localizedName) [\($0.deviceType.rawValue)]" })
    }

    /// Every camera any known device type finds, at every position, plus constituents.
    static func discover() -> (devices: [AVCaptureDevice], report: [String]) {
        var seen = Set<String>()
        var out: [AVCaptureDevice] = []
        var report: [String] = []
        for (label, type) in knownTypes() {
            for pos in [AVCaptureDevice.Position.unspecified, .front, .back] {
                let found = AVCaptureDevice.DiscoverySession(deviceTypes: [type], mediaType: .video, position: pos).devices
                if pos == .unspecified {
                    report.append("device type \(label) [\(type.rawValue)]: \(found.count) camera(s)")
                }
                for d in found where !seen.contains(d.uniqueID) {
                    seen.insert(d.uniqueID)
                    out.append(d)
                }
            }
        }
        let virtualFront = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
                                                            mediaType: .video, position: .front).devices
        report.append("virtual front camera query (wide + ultra wide, front): "
                      + (virtualFront.isEmpty ? "nothing"
                         : virtualFront.map { "\($0.localizedName) virtual=\($0.isVirtualDevice)" }.joined(separator: "; ")))
        let snapshot = out
        for d in snapshot where d.isVirtualDevice {
            for c in d.constituentDevices where !seen.contains(c.uniqueID) {
                seen.insert(c.uniqueID)
                out.append(c)
                report.append("found only as a constituent of \(d.localizedName): \(c.localizedName) [\(c.deviceType.rawValue)]")
            }
        }
        return (out, report)
    }

    /// The camera to use as "the inner camera", best first. On the iPad this falls back
    /// to the ordinary front camera and says so in `note`.
    static func pickInner(testerPick: String?) -> CameraChoice? {
        var innerTypes: [AVCaptureDevice.DeviceType] = nativeDuoTypes()
            .filter { $0.0.hasPrefix("builtInInner") }
            .map { $0.1 }
        if innerTypes.isEmpty, let found = runtimeDeviceType(innerSymbol) {
            innerTypes = [found.type]
        }
        if !innerTypes.isEmpty,
           let d = AVCaptureDevice.DiscoverySession(deviceTypes: innerTypes, mediaType: .video, position: .unspecified).devices.first {
            return CameraChoice(id: d.uniqueID, label: d.localizedName,
                                note: "Duo inner camera, found by its 27.1 device type (\(d.deviceType.rawValue))",
                                isDuoInner: true)
        }
        if let id = testerPick, let d = AVCaptureDevice(uniqueID: id) {
            return CameraChoice(id: d.uniqueID, label: d.localizedName,
                                note: "the camera the tester picked in P2",
                                isDuoInner: d.deviceType.rawValue.contains("Inner"))
        }
        let fronts = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
                                                      mediaType: .video, position: .front).devices
        for f in fronts {
            for c in f.constituentDevices where c.deviceType.rawValue.contains("Inner") {
                return CameraChoice(id: c.uniqueID, label: c.localizedName,
                                    note: "inner constituent of the virtual front camera",
                                    isDuoInner: true)
            }
        }
        if let f = fronts.first {
            let note = f.isVirtualDevice
                ? "virtual front camera: the system picks which physical camera streams (see activePrimaryConstituent)"
                : "FALLBACK: ordinary front camera, not a Duo inner camera"
            return CameraChoice(id: f.uniqueID, label: f.localizedName, note: note, isDuoInner: false)
        }
        if let any = AVCaptureDevice.default(for: .video) {
            return CameraChoice(id: any.uniqueID, label: any.localizedName,
                                note: "FALLBACK: default camera (no front camera found)", isDuoInner: false)
        }
        return nil
    }

    static func rearWide() -> CameraChoice? {
        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return nil }
        return CameraChoice(id: d.uniqueID, label: d.localizedName, note: "rear wide camera", isDuoInner: false)
    }
}
