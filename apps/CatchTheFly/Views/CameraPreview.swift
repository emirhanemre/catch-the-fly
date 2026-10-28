import AVFoundation
import SwiftUI
import UIKit

/// A UIView whose layer is the capture preview. It also tells the game its size (for the
/// aspect-fill crop) and hosts the hinge interaction and haptic generators.
final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees the type.
        return layer as! AVCaptureVideoPreviewLayer
    }

    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }
}

struct CameraPreview: UIViewRepresentable {
    let game: GameController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        game.attach(previewView: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
