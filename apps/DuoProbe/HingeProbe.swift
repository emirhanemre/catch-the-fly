import Foundation
import UIKit
import SwiftUI
import ObjectiveC

struct ProbeHingeSample: Sendable {
    let t: TimeInterval
    let angle: Double?      // radians, as reported
    let statusRaw: Int?     // raw UIHingeStatus integer (mapping unverified, so we log it)
    let hasHinge: Bool      // false when update.hinge was nil
}

struct ProbeHingeExtract: Sendable {
    let sample: ProbeHingeSample
    let note: String?
}

/// Hinge angle and status.
/// Playgrounds build (iOS 26 SDK): UIHingeInteraction through the Objective-C runtime,
/// following API_NOTES section 6, logging each step so a failure names the step.
/// CI build (IOS_27_1_SDK): the native UIHingeInteraction(updateHandler:).
@MainActor
final class HingeProbe: ObservableObject {
    @Published private(set) var availability = "not checked yet"
    @Published private(set) var isAvailable = false
    @Published private(set) var latest: ProbeHingeSample?
    @Published private(set) var sampleCount = 0

    private(set) var samples: [ProbeHingeSample] = []
    let latestBox = LockedBox<ProbeHingeSample?>(nil)
    var logEachSample = false
    var onSample: ((ProbeHingeSample) -> Void)?

    private var interaction: AnyObject?
    private weak var hostView: UIView?
    private var loggedNotes = Set<String>()
    private let testID: String
    private let log: ProbeLog

    init(testID: String, log: ProbeLog) {
        self.testID = testID
        self.log = log
    }

    var readout: String {
        var s = "Hinge: \(availability)\nsamples \(sampleCount)"
        if let l = latest {
            if let a = l.angle {
                s += ", angle \(fmt(a, 3)) rad (\(degText(a)))"
            } else {
                s += ", angle -"
            }
            s += ", status raw \(l.statusRaw.map { "\($0)" } ?? "-")"
            if !l.hasHinge { s += " (no hinge in update)" }
        }
        return s
    }

    func resetSamples() {
        samples.removeAll()
        sampleCount = 0
    }

    func attach(to view: UIView) {
        if let existing = interaction as? UIInteraction {
            if hostView !== view {
                hostView?.removeInteraction(existing)
                view.addInteraction(existing)
                hostView = view
                log.add(testID, "hinge interaction moved to a new view")
            }
            return
        }
        var on271 = false
        if #available(iOS 27.1, *) { on271 = true }
        log.add(testID, "hinge step 0: running on \(on271 ? "iOS 27.1 or later" : "iOS older than 27.1")")

        #if IOS_27_1_SDK
        if #available(iOS 27.1, *) {
            attachNative(to: view)
            return
        }
        #endif
        attachViaRuntime(to: view)
    }

    #if IOS_27_1_SDK
    @available(iOS 27.1, *)
    private func attachNative(to view: UIView) {
        let inter = UIHingeInteraction(updateHandler: { [weak self] _, update in
            // UIKit calls this on the main actor. assumeIsolated keeps it compiling whether
            // the SDK types the handler as @MainActor or as plain/@Sendable.
            MainActor.assumeIsolated {
                let t = ProcessInfo.processInfo.systemUptime
                if let h = update.hinge {
                    let raw = h.status.rawValue
                    let name: String
                    switch h.status {
                    case .closed: name = "closed"
                    case .partiallyOpen: name = "partiallyOpen"
                    case .fullyOpen: name = "fullyOpen"
                    case .unknown: name = "unknown"
                    @unknown default: name = "other"
                    }
                    self?.record(ProbeHingeSample(t: t, angle: Double(h.angle), statusRaw: raw, hasHinge: true),
                                 note: "native status raw \(raw) = .\(name)")
                } else {
                    self?.record(ProbeHingeSample(t: t, angle: nil, statusRaw: nil, hasHinge: false),
                                 note: "update.hinge is nil")
                }
            }
        })
        view.addInteraction(inter)
        interaction = inter
        hostView = view
        isAvailable = true
        availability = "native UIHingeInteraction (SDK 27.1 build); waiting for first update"
        log.add(testID, "hinge: native UIHingeInteraction attached, isEnabled = \(inter.isEnabled)")
        checkForUpdatesLater()
    }
    #endif

    private func attachViaRuntime(to view: UIView) {
        guard let cls: AnyClass = NSClassFromString("UIHingeInteraction") else {
            fail(1, "NSClassFromString(\"UIHingeInteraction\") returned nil: the class doesn't exist on this device")
            return
        }
        log.add(testID, "hinge step 1 OK: class UIHingeInteraction exists")
        let initSel = NSSelectorFromString("initWithUpdateHandler:")
        guard let objcClass = cls as? NSObject.Type, objcClass.instancesRespond(to: initSel) else {
            fail(2, "UIHingeInteraction doesn't respond to initWithUpdateHandler:")
            return
        }
        log.add(testID, "hinge step 2 OK: responds to initWithUpdateHandler:")
        let allocSel = NSSelectorFromString("alloc")
        guard let allocMethod = class_getClassMethod(cls, allocSel) else {
            fail(3, "class_getClassMethod(alloc) returned nil")
            return
        }
        guard let initMethod = class_getInstanceMethod(cls, initSel) else {
            fail(4, "class_getInstanceMethod(initWithUpdateHandler:) returned nil")
            return
        }
        // ObjC ABI: +alloc returns a +1 object; -init… consumes that +1 and returns a new
        // +1 (or nil, having released the allocation). Raw pointers keep ARC out of the
        // middle, and takeRetainedValue() balances the final +1 exactly once.
        typealias AllocFn = @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer?
        typealias HandlerBlock = @convention(block) (AnyObject, AnyObject) -> Void
        typealias InitFn = @convention(c) (UnsafeMutableRawPointer, Selector, HandlerBlock) -> UnsafeMutableRawPointer?
        let allocFn = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFn.self)
        let initFn = unsafeBitCast(method_getImplementation(initMethod), to: InitFn.self)
        guard let allocated = allocFn(cls as AnyObject, allocSel) else {
            fail(5, "alloc returned nil")
            return
        }
        let handler: HandlerBlock = { [weak self] _, update in
            // UIKit calls this on the main thread (the interaction is @MainActor).
            let extract = HingeProbe.extract(update)
            MainActor.assumeIsolated {
                self?.record(extract.sample, note: extract.note)
            }
        }
        guard let initialised = initFn(allocated, initSel, handler) else {
            fail(6, "initWithUpdateHandler: returned nil")
            return
        }
        let object: AnyObject = Unmanaged<AnyObject>.fromOpaque(initialised).takeRetainedValue()
        guard let inter = object as? UIInteraction else {
            fail(7, "the new object isn't a UIInteraction")
            return
        }
        view.addInteraction(inter)
        interaction = object
        hostView = view
        isAvailable = true
        availability = "UIHingeInteraction via runtime; waiting for first update"
        var enabledText = "unknown"
        if let o = object as? NSObject, o.responds(to: NSSelectorFromString("isEnabled")) {
            enabledText = "\((o.value(forKey: "enabled") as? NSNumber)?.boolValue ?? false)"
        }
        log.add(testID, "hinge step 7 OK: interaction created and added to a view, isEnabled = \(enabledText)")
        checkForUpdatesLater()
    }

    private func fail(_ step: Int, _ why: String) {
        availability = "not available (step \(step): \(why))"
        isAvailable = false
        log.result(testID, .notAvailable, "hinge runtime path failed at step \(step): \(why)")
    }

    private func checkForUpdatesLater() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            if self.samples.isEmpty {
                self.log.add(self.testID, "hinge: no update arrived within 2 s of attaching")
            }
        }
    }

    /// Reads hinge.angle and hinge.status by key-value coding, checking each selector first.
    nonisolated static func extract(_ update: AnyObject) -> ProbeHingeExtract {
        let t = ProcessInfo.processInfo.systemUptime
        let empty = ProbeHingeSample(t: t, angle: nil, statusRaw: nil, hasHinge: false)
        guard let upd = update as? NSObject else {
            return ProbeHingeExtract(sample: empty, note: "update isn't an NSObject")
        }
        guard upd.responds(to: NSSelectorFromString("hinge")) else {
            return ProbeHingeExtract(sample: empty, note: "update has no 'hinge' property")
        }
        guard let hinge = upd.value(forKey: "hinge") as? NSObject else {
            return ProbeHingeExtract(sample: empty, note: "update.hinge is nil")
        }
        var angle: Double?
        var status: Int?
        var notes: [String] = []
        if hinge.responds(to: NSSelectorFromString("angle")) {
            angle = (hinge.value(forKey: "angle") as? NSNumber)?.doubleValue
        } else {
            notes.append("hinge has no 'angle'")
        }
        if hinge.responds(to: NSSelectorFromString("status")) {
            status = (hinge.value(forKey: "status") as? NSNumber)?.intValue
        } else {
            notes.append("hinge has no 'status'")
        }
        return ProbeHingeExtract(sample: ProbeHingeSample(t: t, angle: angle, statusRaw: status, hasHinge: true),
                            note: notes.isEmpty ? nil : notes.joined(separator: "; "))
    }

    private func record(_ sample: ProbeHingeSample, note: String?) {
        if samples.isEmpty {
            log.add(testID, "hinge: first update arrived", at: sample.t)
            availability = availability.replacingOccurrences(of: "; waiting for first update", with: "; receiving updates")
        }
        if let note, !loggedNotes.contains(note) {
            loggedNotes.insert(note)
            log.add(testID, "hinge note: \(note)", at: sample.t)
        }
        samples.append(sample)
        sampleCount = samples.count
        latest = sample
        latestBox.set(sample)
        if logEachSample {
            let a = sample.angle.map { "\(fmt($0, 4)) rad (\(degText($0)))" } ?? "nil"
            let s = sample.statusRaw.map { "\($0)" } ?? "nil"
            log.add(testID, "hinge sample: angle \(a), status raw \(s), hinge present \(sample.hasHinge)", at: sample.t)
        }
        onSample?(sample)
    }
}

/// An invisible UIView that carries the hinge interaction.
struct HingeHost: UIViewRepresentable {
    let probe: HingeProbe

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        probe.attach(to: v)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
