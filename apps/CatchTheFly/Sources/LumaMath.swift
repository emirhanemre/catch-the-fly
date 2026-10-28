import Foundation
import CoreVideo

/// Read-only access to the luma (Y) plane of a camera pixel buffer. Capture queue only.
enum LumaMath {
    /// A locked Y plane. Only valid inside `withLumaPlane`.
    struct Plane {
        let base: UnsafePointer<UInt8>
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let videoRange: Bool

        /// Luma 0...1 at a pixel (no bounds check: callers stay inside width × height).
        func value(x: Int, y: Int) -> Double {
            let raw = Double(base[y * bytesPerRow + x])
            if videoRange {
                return min(1, max(0, (raw - 16) / 219))
            }
            return raw / 255
        }
    }

    /// Locks the buffer, hands the Y plane to `body`, unlocks. Returns nil for non-YUV formats.
    static func withLumaPlane<T>(_ pixelBuffer: CVPixelBuffer, _ body: (Plane) -> T) -> T? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isFull = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let isVideo = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        guard isFull || isVideo, CVPixelBufferIsPlanar(pixelBuffer), CVPixelBufferGetPlaneCount(pixelBuffer) >= 1 else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let raw = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bpr = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard width > 0, height > 0, bpr >= width else { return nil }
        let typed = raw.assumingMemoryBound(to: UInt8.self)
        let plane = Plane(base: UnsafePointer(typed), width: width, height: height, bytesPerRow: bpr, videoRange: isVideo)
        return body(plane)
    }

    /// Mean luma 0...1 over a sparse grid (about 4,000 samples).
    static func meanLuma(_ pixelBuffer: CVPixelBuffer) -> Double? {
        return withLumaPlane(pixelBuffer) { plane -> Double in
            let step = max(4, min(plane.width, plane.height) / 48)
            var sum = 0.0
            var count = 0
            var y = step / 2
            while y < plane.height {
                var x = step / 2
                while x < plane.width {
                    sum += plane.value(x: x, y: y)
                    count += 1
                    x += step
                }
                y += step
            }
            return count > 0 ? sum / Double(count) : 0
        }
    }

    /// Mean and standard deviation of luma in a pixel rectangle, sampled every `step` pixels.
    static func stats(_ plane: Plane, x0: Int, y0: Int, size: Int, step: Int) -> (mean: Double, stdDev: Double) {
        var sum = 0.0
        var sumSq = 0.0
        var n = 0.0
        let x1 = min(plane.width, x0 + size)
        let y1 = min(plane.height, y0 + size)
        var y = max(0, y0)
        while y < y1 {
            var x = max(0, x0)
            while x < x1 {
                let v = plane.value(x: x, y: y)
                sum += v
                sumSq += v * v
                n += 1
                x += step
            }
            y += step
        }
        if n < 1 { return (0, 0) }
        let mean = sum / n
        let variance = max(0, sumSq / n - mean * mean)
        return (mean, variance.squareRoot())
    }
}
