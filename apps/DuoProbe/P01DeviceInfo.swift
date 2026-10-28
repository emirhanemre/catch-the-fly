import SwiftUI
import UIKit
import ARKit
import AVFoundation
import AVKit
import ObjectiveC
import Darwin

@MainActor
enum DeviceInfoProbe {
    static let runtimeClassNames = [
        "UIHingeInteraction", "UIHingeInteractionUpdate", "UIHinge",
        "UISceneAccessory", "UISceneAccessoryRegistration",
        "AVCaptureDeviceDirectionCoordinator", "AVCaptureDeviceDirectionMap", "AVCaptureDeviceDescriptor"
    ]

    static var buildKind: String {
        #if IOS_27_1_SDK
        return "SDK 27.1 native (CI build)"
        #else
        return "Playgrounds runtime (iOS 26 SDK, runtime lookups)"
        #endif
    }

    static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    static func idiomName(_ idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .phone: return "phone"
        case .pad: return "pad"
        case .tv: return "tv"
        case .carPlay: return "carPlay"
        case .mac: return "mac"
        case .vision: return "vision"
        case .unspecified: return "unspecified"
        @unknown default: return "other(\(idiom.rawValue))"
        }
    }

    static func run(log: ProbeLog) {
        let id = "P1"
        log.add(id, "---- P1 device and support flags ----")
        log.result(id, .value, "build = \(buildKind)")
        log.result(id, .value, "model identifier = \(modelIdentifier())")
        let dev = UIDevice.current
        log.result(id, .value, "\(dev.systemName) \(dev.systemVersion), model \(dev.model), idiom \(idiomName(dev.userInterfaceIdiom))")
        var on271 = false
        if #available(iOS 27.1, *) { on271 = true }
        log.result(id, .value, "#available(iOS 27.1) = \(on271)")
        for line in DisplayInfo.describeScenes() {
            log.result(id, .value, line)
        }
        log.result(id, .value, "ARWorldTrackingConfiguration.isSupported = \(ARWorldTrackingConfiguration.isSupported)")
        log.result(id, .value, "ARWorldTrackingConfiguration.supportsUserFaceTracking = \(ARWorldTrackingConfiguration.supportsUserFaceTracking)")
        log.result(id, .value, "ARFaceTrackingConfiguration.isSupported = \(ARFaceTrackingConfiguration.isSupported)")
        log.result(id, .value, "ARFaceTrackingConfiguration.supportsWorldTracking = \(ARFaceTrackingConfiguration.supportsWorldTracking)")
        log.result(id, .value, "AVCaptureMultiCamSession.isMultiCamSupported = \(AVCaptureMultiCamSession.isMultiCamSupported)")

        for name in runtimeClassNames {
            let found = NSClassFromString(name) != nil
            log.result(id, .value, "NSClassFromString(\"\(name)\") = \(found ? "found" : "nil")")
        }
        if let cls = NSClassFromString("UIHingeInteraction") as? NSObject.Type {
            let ok = cls.instancesRespond(to: NSSelectorFromString("initWithUpdateHandler:"))
            log.result(id, .value, "UIHingeInteraction responds to initWithUpdateHandler: = \(ok)")
        }
        if let cls: AnyClass = NSClassFromString("UISceneAccessory") {
            let ok = class_getClassMethod(cls, NSSelectorFromString("cameraCaptureSceneAccessoryWithConfiguration:")) != nil
            log.result(id, .value, "UISceneAccessory has +cameraCaptureSceneAccessoryWithConfiguration: = \(ok)")
        }
        let registers = UIViewController.instancesRespond(to: NSSelectorFromString("registerSceneAccessory:"))
        log.result(id, .value, "UIViewController responds to registerSceneAccessory: (selector name guessed) = \(registers)")

        for symbol in [CameraFinder.innerSymbol, CameraFinder.outerSymbol] {
            log.result(id, .value, "exported constant \(symbol) = \(CameraFinder.exportedString(symbol) ?? "not found")")
        }
        for (label, type) in CameraFinder.nativeDuoTypes() {
            log.result(id, .value, "native \(label) rawValue = \(type.rawValue)")
        }
        log.result(id, .pass, "P1 finished")
    }
}

struct P1View: View {
    let log: ProbeLog
    @State var ran = false

    var body: some View {
        TestPage(id: "P1", title: "Device info", steps: [
            "Hold the phone however you like.",
            "Tap Run. It takes a second and records what this phone supports."
        ], log: log) {
            BigButton(ran ? "Run again" : "Run") {
                DeviceInfoProbe.run(log: log)
                ran = true
            }
            if ran {
                Text("Done. You can go back and start P2.")
                    .font(.callout)
            }
        }
    }
}
