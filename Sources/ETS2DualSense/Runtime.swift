import AppKit
import DualSenseKit
import EffectKit
import Foundation

/// What the UI shows; rebuilt by the runtime a few times per second.
struct Snapshot {
    var device: DeviceInfo?
    var input = InputState()
    var truck = TruckState()
    var pluginSeen = false          // telemetry file exists
    var sdkActive = false
    var telemetryLive = false
    var telemetryAgeMs = 0.0
    var source = "None"
    var output = OutputState()
    var active: ActiveEffects = []
    var stats = TransportStats()
    var tickMicros = 0.0
    var maxTickMicros = 0.0
    var tickRate = 0.0
    var framesPerSecond = 0.0       // telemetry frames published by the game
}

/// The 60 Hz loop: telemetry in, effects computed, HID reports out. Runs off the main thread.
final class Runtime: @unchecked Sendable {
    let manager = DualSenseManager()
    var onSnapshot: (@Sendable (Snapshot) -> Void)?
    var onLog: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "effects", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    // Guarded by `lock`: set from the main thread, read by the loop.
    private var profile = Profile.original
    private var enabled = true
    private var demo = false
    private var gameRunning = false
    private var manual: TruckState?
    private var preview: (EffectPreview, Double)?
    private var forceResend = false

    // Loop-only state.
    private let reader = TelemetryReader()
    private var engine = EffectEngine()
    private var previewEngine = EffectEngine()
    private var simulator = TelemetrySimulator()
    private var rim = RimSteering()
    private let steering = SteeringWriter()
    private var rimWasOn = false
    private var driving = false
    private var wasLive = false
    private var tick = 0
    private var maxTick = 0.0
    private var lastSeq: UInt32 = 0
    private var seqWindow: (UInt32, Double) = (0, 0)
    private var fps = 0.0
    private var tickWindow: (Int, Double) = (0, 0)
    private var tickRate = 0.0
    private var lastSource = ""
    private var busy = true

    func set(profile p: Profile) { lock.withLock { profile = p } }
    func set(enabled e: Bool) { lock.withLock { enabled = e } }
    func set(demo d: Bool) { lock.withLock { demo = d } }
    func set(gameRunning g: Bool) { lock.withLock { gameRunning = g } }
    func set(manual t: TruckState?) { lock.withLock { manual = t } }
    func play(_ p: EffectPreview) { lock.withLock { preview = (p, Self.now()) } }
    func resend() { lock.withLock { forceResend = true } }

    static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    func start() {
        manager.onLog = { [weak self] in self?.onLog?($0) }
        manager.onConnectionChange = { [weak self] _ in self?.resend() }
        manager.start()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: EffectEngine.frameInterval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.step() }
        t.resume()
        timer = t
    }

    /// Stops the loop and returns the controller to its neutral state. Safe to call more than once.
    func shutdown() {
        queue.sync {
            timer?.cancel()
            timer = nil
            steering.stop()
            manager.reset()
        }
    }

    /// Neutral state now (before sleep); the loop resumes by itself.
    func park() {
        queue.sync {
            manager.reset()
            driving = false
        }
    }

    private func step() {
        tick += 1
        // With nothing to drive (no game frames, no preview) a tenth of the rate is plenty.
        let wanted = lock.withLock { demo || manual != nil || preview != nil || forceResend }
        if !busy && !wanted && tick % 6 != 0 { return }
        let started = Self.now()
        let (profile, enabled, demo, gameRunning, manual, previewState, force) = lock.withLock {
            () -> (Profile, Bool, Bool, Bool, TruckState?, (EffectPreview, Double)?, Bool) in
            if let (p, start) = preview, started - start > p.duration { preview = nil }
            defer { forceResend = false }
            return (profile, enabled, demo, gameRunning, manual, preview, forceResend)
        }

        var snap = Snapshot()
        let sample = reader.read()
        if let sample {
            snap.pluginSeen = true
            snap.sdkActive = sample.sdkActive && (sample.ageMs < 2000 || gameRunning)
            snap.telemetryAgeMs = sample.ageMs
            // Frames stop while the game sits in a menu; that still counts as connected.
            snap.telemetryLive = sample.sdkActive && (sample.ageMs < 2000 || (sample.truck.paused && gameRunning))
            if seqWindow.1 == 0 { seqWindow = (sample.frameSeq, started) }
            if started - seqWindow.1 >= 1 {
                fps = Double(sample.frameSeq &- seqWindow.0) / 2 / (started - seqWindow.1)
                seqWindow = (sample.frameSeq, started)
            }
            snap.framesPerSecond = fps
        }

        // Pick the telemetry that drives the controller this frame.
        var truck: TruckState?
        var result: (output: OutputState, active: ActiveEffects)?
        if let (p, start) = previewState {
            snap.source = "Preview"
            let t = p.truck(at: started - start)
            if started - start < EffectEngine.frameInterval * 1.5 { previewEngine.reset() }
            result = previewEngine.step(t, profile: p.enabling(in: profile), now: started)
            truck = sample?.truck
        } else if let manual {
            snap.source = "Manual test"
            result = previewEngine.step(manual, profile: profile, now: started)
            truck = sample?.truck
        } else if demo {
            snap.source = "Demo drive"
            let t = simulator.step()
            truck = t
            if enabled { result = engine.step(t, profile: profile, now: started) }
        } else if let sample, snap.telemetryLive {
            snap.source = sample.truck.game == 2 ? "American Truck Simulator" : "Euro Truck Simulator 2"
            truck = sample.truck
            // In a menu the controller is left alone (the engine still sees the frame so it stays primed).
            let r = engine.step(sample.truck, profile: profile, now: started)
            if enabled && !sample.truck.paused { result = r }
        } else {
            truck = sample?.truck
        }
        let live = demo || snap.telemetryLive
        if !live && wasLive { engine.reset() }
        wasLive = live
        if snap.source != lastSource {
            onLog?("Effect source: \(snap.source)")
            lastSource = snap.source
        }

        // Rim steering needs the live game.
        if profile.rim.enabled, enabled, snap.telemetryLive, let t = sample?.truck, !t.paused, manager.device != nil {
            let i = manager.input
            steering.write(rim.step(x: Int(i.leftX) - 128, y: 127 - Int(i.leftY), speedMs: t.speed, config: profile.rim))
            rimWasOn = true
        } else if rimWasOn {
            steering.stop()
            rimWasOn = false
        }

        if let result {
            if !manager.send(result.output, force: force), manager.device != nil, tick % 120 == 0 {
                onLog?("HID write failed: \(DualSenseManager.describe(manager.stats.lastResult))")
            }
            driving = true
            snap.output = result.output
            snap.active = result.active
        } else if driving || force {
            // Nothing to drive: release the triggers and hand the LEDs back once, then stay quiet.
            manager.reset()
            driving = false
        }

        busy = wanted || (snap.telemetryLive && !(sample?.truck.paused ?? true))
        let micros = (Self.now() - started) * 1e6
        maxTick = max(maxTick, micros)
        if tickWindow.1 == 0 { tickWindow = (tick, started) }
        if started - tickWindow.1 >= 1 {
            tickRate = Double(tick - tickWindow.0) / (started - tickWindow.1)
            tickWindow = (tick, started)
        }
        if tick % (busy ? 6 : 18) == 0 {
            snap.device = manager.device
            snap.input = manager.input
            snap.stats = manager.stats
            snap.truck = truck ?? TruckState()
            snap.tickMicros = micros
            snap.maxTickMicros = maxTick
            snap.tickRate = tickRate
            onSnapshot?(snap)
        }
    }
}
