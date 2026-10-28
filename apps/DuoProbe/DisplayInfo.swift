import Foundation
import UIKit
import SwiftUI

/// Text descriptions of scenes, screens, windows and traits. Never uses UIScreen.main.
@MainActor
enum DisplayInfo {
    static func size(_ s: CGSize) -> String {
        "\(Int(s.width))x\(Int(s.height))"
    }

    static func sizeClass(_ c: UIUserInterfaceSizeClass) -> String {
        switch c {
        case .compact: return "compact"
        case .regular: return "regular"
        case .unspecified: return "unspecified"
        @unknown default: return "other"
        }
    }

    static func activation(_ s: UIScene.ActivationState) -> String {
        switch s {
        case .foregroundActive: return "foregroundActive"
        case .foregroundInactive: return "foregroundInactive"
        case .background: return "background"
        case .unattached: return "unattached"
        @unknown default: return "other"
        }
    }

    static func orientation(_ o: UIInterfaceOrientation) -> String {
        switch o {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .unknown: return "unknown"
        @unknown default: return "other"
        }
    }

    static func screenID(_ screen: UIScreen) -> String {
        "\(ObjectIdentifier(screen))"
            .replacingOccurrences(of: "ObjectIdentifier(", with: "screen ")
            .replacingOccurrences(of: ")", with: "")
    }

    /// One line per connected scene.
    static func describeScenes() -> [String] {
        var out: [String] = []
        for scene in UIApplication.shared.connectedScenes {
            var s = "scene role \(scene.session.role.rawValue), \(activation(scene.activationState))"
            if let ws = scene as? UIWindowScene {
                let scr = ws.screen
                s += "; \(screenID(scr)) bounds \(size(scr.bounds.size)) native \(size(scr.nativeBounds.size)) scale \(fmt(Double(scr.scale), 1))"
                s += "; size class h \(sizeClass(ws.traitCollection.horizontalSizeClass)) v \(sizeClass(ws.traitCollection.verticalSizeClass))"
                if #available(iOS 16.0, *) {
                    s += "; orientation \(orientation(ws.effectiveGeometry.interfaceOrientation))"
                }
                for w in ws.windows {
                    s += "; window \(size(w.bounds.size))\(w.isKeyWindow ? " (key)" : "")"
                }
            }
            out.append(s)
        }
        if out.isEmpty { out.append("no connected scenes") }
        return out
    }

    /// Geometry as seen from one view inside the window.
    static func describeView(_ v: UIView) -> String {
        var s = "view \(size(v.bounds.size))"
        if let w = v.window {
            s += ", window \(size(w.bounds.size))"
            if let ws = w.windowScene {
                s += ", \(screenID(ws.screen)) \(size(ws.screen.bounds.size)) @\(fmt(Double(ws.screen.scale), 0))x"
                s += ", role \(ws.session.role.rawValue)"
                if #available(iOS 16.0, *) {
                    s += ", orientation \(orientation(ws.effectiveGeometry.interfaceOrientation))"
                }
            }
        } else {
            s += ", not in a window"
        }
        let tc = v.traitCollection
        s += ", size class h \(sizeClass(tc.horizontalSizeClass)) v \(sizeClass(tc.verticalSizeClass)), displayScale \(fmt(Double(tc.displayScale), 1))"
        return s
    }
}

/// An invisible view that reports every change in its geometry, window, screen or size
/// classes (it checks on every layout pass and when it moves between windows).
struct WindowWatcher: UIViewRepresentable {
    let onChange: (String) -> Void

    func makeUIView(context: Context) -> WatcherView {
        let v = WatcherView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.onChange = onChange
        return v
    }

    func updateUIView(_ uiView: WatcherView, context: Context) {
        uiView.onChange = onChange
    }
}

final class WatcherView: UIView {
    var onChange: ((String) -> Void)?
    private var last = ""

    override func layoutSubviews() {
        super.layoutSubviews()
        report()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    private func report() {
        let s = DisplayInfo.describeView(self)
        if s != last {
            last = s
            onChange?(s)
        }
    }
}

/// Logs app and scene lifecycle notifications for the whole session (tag SYS).
@MainActor
final class SystemMonitor: ObservableObject {
    private var tokens: [NSObjectProtocol] = []
    private var started = false

    func start(log: ProbeLog) {
        guard !started else { return }
        started = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let watched: [(Notification.Name, String, Bool)] = [
            (UIApplication.didBecomeActiveNotification, "app didBecomeActive", true),
            (UIApplication.willResignActiveNotification, "app willResignActive", true),
            (UIApplication.didEnterBackgroundNotification, "app didEnterBackground", true),
            (UIApplication.willEnterForegroundNotification, "app willEnterForeground", true),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "protected data will become unavailable (locking)", false),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "protected data available again (unlocked)", false),
            (UIScene.willConnectNotification, "scene willConnect", true),
            (UIScene.didDisconnectNotification, "scene didDisconnect", true),
            (UIScene.didActivateNotification, "scene didActivate", true),
            (UIScene.willDeactivateNotification, "scene willDeactivate", true),
            (UIScene.willEnterForegroundNotification, "scene willEnterForeground", false),
            (UIScene.didEnterBackgroundNotification, "scene didEnterBackground", false),
            (UIDevice.orientationDidChangeNotification, "device orientation changed", false)
        ]
        for (name, label, withScenes) in watched {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                let t = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in
                    var text = label
                    if label == "device orientation changed" {
                        text += ": raw \(UIDevice.current.orientation.rawValue)"
                    }
                    log.system(text, at: t)
                    if withScenes {
                        for line in DisplayInfo.describeScenes() {
                            log.system("  " + line, at: t)
                        }
                    }
                }
            }
            tokens.append(token)
        }
        log.system("system monitor started")
        for line in DisplayInfo.describeScenes() {
            log.system("  " + line)
        }
    }
}
