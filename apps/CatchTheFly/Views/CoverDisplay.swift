import SwiftUI

/// Phase 4 and the Playgrounds build: no cover-display content (the iPad has one screen, and
/// CameraCaptureAccessory needs the iOS 27.1 SDK). A native version goes in its own file under
/// `#if IOS_27_1_SDK` and is chosen in `Platform.coverDisplay(game:)`.
struct NoCoverDisplay: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
