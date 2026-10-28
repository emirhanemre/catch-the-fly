import Foundation
import ObjectiveC
import UIKit

/// Reaches UIHingeInteraction (iOS 27.1) without naming it at compile time (API_NOTES section 6).
///
/// UNTESTED pattern. Differences from the API_NOTES sketch, on purpose:
/// - `@convention(c)` can't take `Any`, so every argument is a raw pointer;
/// - ownership is explicit: `+alloc` returns +1, `-initWithUpdateHandler:` consumes it and
///   returns +1, which `takeRetainedValue()` balances;
/// - every KVC read checks `responds(to:)` first, so a renamed property can't raise.
@MainActor
enum RuntimeHinge {
    static var isClassPresent: Bool {
        return NSClassFromString("UIHingeInteraction") != nil
    }

    /// `onUpdate(angle, statusRaw)` runs on the main thread: with the initial state, then on each
    /// change. (nil, nil) means "no hinge in this hierarchy".
    static func makeInteraction(onUpdate: @escaping (Double?, Int?) -> Void) -> (any UIInteraction)? {
        guard let cls: AnyClass = NSClassFromString("UIHingeInteraction") else { return nil }
        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("initWithUpdateHandler:")
        guard let allocMethod = class_getClassMethod(cls, allocSel),
              let initMethod = class_getInstanceMethod(cls, initSel) else { return nil }

        typealias AllocFn = @convention(c) (UnsafeRawPointer, Selector) -> UnsafeMutableRawPointer?
        typealias InitFn = @convention(c) (UnsafeMutableRawPointer, Selector, UnsafeRawPointer) -> UnsafeMutableRawPointer?
        let allocFn = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFn.self)
        let initFn = unsafeBitCast(method_getImplementation(initMethod), to: InitFn.self)

        let hingeSel = NSSelectorFromString("hinge")
        let angleSel = NSSelectorFromString("angle")
        let statusSel = NSSelectorFromString("status")
        let block: @convention(block) (AnyObject, AnyObject) -> Void = { _, update in
            guard let u = update as? NSObject, u.responds(to: hingeSel),
                  let hinge = u.value(forKey: "hinge") as? NSObject else {
                onUpdate(nil, nil)
                return
            }
            var angle: Double? = nil
            var status: Int? = nil
            if hinge.responds(to: angleSel) {
                angle = (hinge.value(forKey: "angle") as? NSNumber)?.doubleValue
            }
            if hinge.responds(to: statusSel) {
                status = (hinge.value(forKey: "status") as? NSNumber)?.intValue
            }
            onUpdate(angle, status)
        }
        let blockObject: AnyObject = unsafeBitCast(block, to: AnyObject.self)
        let classObject: AnyObject = cls as AnyObject
        let classPtr = UnsafeRawPointer(Unmanaged<AnyObject>.passUnretained(classObject).toOpaque())
        guard let allocated = allocFn(classPtr, allocSel) else { return nil }
        let blockPtr = UnsafeRawPointer(Unmanaged<AnyObject>.passUnretained(blockObject).toOpaque())
        let result = withExtendedLifetime(blockObject) {
            initFn(allocated, initSel, blockPtr)
        }
        guard let objectPtr = result else { return nil }
        let object = Unmanaged<AnyObject>.fromOpaque(objectPtr).takeRetainedValue()
        return object as? UIInteraction
    }
}
