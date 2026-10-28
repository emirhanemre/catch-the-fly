import Foundation
import AVFoundation

/// All sound is synthesised here: no audio assets. The buzz loops on one player node and takes
/// FlyCore's pan and gain every frame; one-off effects play on a second node.
@MainActor
final class GameAudio {
    enum Effect {
        case hit
        case miss
        case alarm
        case fanfare
    }

    private let engine = AVAudioEngine()
    private let buzzNode = AVAudioPlayerNode()
    private let effectNode = AVAudioPlayerNode()
    private var buzz: AVAudioPCMBuffer?
    private var hit: AVAudioPCMBuffer?
    private var miss: AVAudioPCMBuffer?
    private var alarm: AVAudioPCMBuffer?
    private var fanfare: AVAudioPCMBuffer?
    private var started = false
    private var smoothedGain: Float = 0

    private static let sampleRate = 44_100.0

    /// Returns a line for the session log.
    func start() -> String {
        guard !started else { return restartIfNeeded() }
        var report = "AUDIO"
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try s.setActive(true)
        } catch {
            report += " session error: \(error.localizedDescription);"
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: GameAudio.sampleRate, channels: 1) else {
            return report + " no audio format"
        }
        buzz = GameAudio.makeBuzz(format: format)
        hit = GameAudio.makeHit(format: format)
        miss = GameAudio.makeMiss(format: format)
        alarm = GameAudio.makeAlarm(format: format)
        fanfare = GameAudio.makeFanfare(format: format)

        engine.attach(buzzNode)
        engine.attach(effectNode)
        engine.connect(buzzNode, to: engine.mainMixerNode, format: format)
        engine.connect(effectNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            return report + " engine error: \(error.localizedDescription)"
        }
        started = true
        if let b = buzz {
            buzzNode.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
        }
        buzzNode.volume = 0
        buzzNode.play()
        effectNode.play()
        return report + " started"
    }

    private func restartIfNeeded() -> String {
        if engine.isRunning { return "AUDIO already running" }
        do {
            try engine.start()
            buzzNode.play()
            effectNode.play()
            return "AUDIO restarted"
        } catch {
            return "AUDIO restart failed: \(error.localizedDescription)"
        }
    }

    /// Every frame: FlyCore's gain (0...1) and pan (-1...1).
    func update(gain: Double, pan: Double) {
        guard started else { return }
        let target = Float(min(1, max(0, gain.isFinite ? gain : 0))) * 0.7
        // A little smoothing so 60 Hz volume steps don't click.
        smoothedGain += (target - smoothedGain) * 0.3
        buzzNode.volume = smoothedGain
        buzzNode.pan = Float(min(1, max(-1, pan.isFinite ? pan : 0)))
    }

    func play(_ effect: Effect) {
        guard started else { return }
        if !engine.isRunning {
            _ = restartIfNeeded()
        }
        let buffer: AVAudioPCMBuffer?
        switch effect {
        case .hit: buffer = hit
        case .miss: buffer = miss
        case .alarm: buffer = alarm
        case .fanfare: buffer = fanfare
        }
        guard let b = buffer else { return }
        effectNode.scheduleBuffer(b, at: nil, options: .interrupts, completionHandler: nil)
        if !effectNode.isPlaying {
            effectNode.play()
        }
    }

    // MARK: Synthesis

    private static func makeBuffer(format: AVAudioFormat, seconds: Double,
                                   _ sample: (_ i: Int, _ t: Double, _ n: Int) -> Float) -> AVAudioPCMBuffer? {
        let n = Int(seconds * sampleRate)
        guard n > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(n)
        let out = channels[0]
        for i in 0..<n {
            out[i] = sample(i, Double(i) / sampleRate, n)
        }
        return buffer
    }

    /// One second that loops seamlessly: every frequency has a whole number of cycles per second.
    /// A sawtooth/square mix around 200 Hz with a 7 Hz and 13 Hz wobble and a 35 Hz wing flutter.
    private static func makeBuzz(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var phase = 0.0
        return makeBuffer(format: format, seconds: 1.0) { _, t, _ in
            let f = 200.0 + 14.0 * sin(2 * Double.pi * 7 * t) + 6.0 * sin(2 * Double.pi * 13 * t)
            phase += f / sampleRate
            phase -= floor(phase)
            let saw = 2 * phase - 1
            let square: Double = phase < 0.5 ? 1 : -1
            let flutter = 0.75 + 0.25 * sin(2 * Double.pi * 35 * t)
            return Float((0.7 * saw + 0.3 * square) * flutter * 0.35)
        }
    }

    /// A wet thud: a falling low sine plus a noise burst, both decaying fast.
    private static func makeHit(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var rng = FlyRNG(seed: 7)
        var phase = 0.0
        return makeBuffer(format: format, seconds: 0.45) { _, t, _ in
            let f = 140.0 * exp(-t * 6) + 45
            phase += f / sampleRate
            let thud = sin(2 * Double.pi * phase) * exp(-t * 9)
            let noise = (rng.nextUnit() * 2 - 1) * exp(-t * 22)
            return Float((0.8 * thud + 0.5 * noise) * 0.8)
        }
    }

    /// The smug fly-off: a buzz that glides up and away.
    private static func makeMiss(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var phase = 0.0
        return makeBuffer(format: format, seconds: 0.6) { _, t, _ in
            let f = 220.0 + 600.0 * t * t / 0.36
            phase += f / sampleRate
            phase -= floor(phase)
            let saw = 2 * phase - 1
            let env = min(1, t * 30) * (1 - t / 0.6)
            return Float(saw * env * 0.35)
        }
    }

    /// Startled: a short, sharp high buzz.
    private static func makeAlarm(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var phase = 0.0
        return makeBuffer(format: format, seconds: 0.18) { _, t, _ in
            let f = 380.0 + 40.0 * sin(2 * Double.pi * 30 * t)
            phase += f / sampleRate
            phase -= floor(phase)
            let square: Double = phase < 0.5 ? 1 : -1
            let env = min(1, t * 80) * (1 - t / 0.18)
            return Float(square * env * 0.18)
        }
    }

    /// Round finished: three rising notes.
    private static func makeFanfare(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes = [523.25, 659.25, 783.99]
        let noteLength = 0.16
        return makeBuffer(format: format, seconds: noteLength * 3 + 0.25) { _, t, _ in
            let index = min(notes.count - 1, Int(t / noteLength))
            let local = t - Double(index) * noteLength
            let env = exp(-local * (index == notes.count - 1 ? 4 : 10))
            return Float(sin(2 * Double.pi * notes[index] * t) * env * 0.3)
        }
    }
}
