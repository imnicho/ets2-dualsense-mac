// Telemetry -> controller output. The "original" paths reproduce ETS2_PS5_Adaptive_Triggers.exe v1.5
// by LikeARealG (constants and ordering follow the Windows binary); everything else is an addition.
import DualSenseKit
import Foundation

public struct ActiveEffects: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let fineAlert = ActiveEffects(rawValue: 1 << 0)
    public static let gearJolt = ActiveEffects(rawValue: 1 << 1)
    public static let cranking = ActiveEffects(rawValue: 1 << 2)
    public static let startLurch = ActiveEffects(rawValue: 1 << 3)
    public static let hardBraking = ActiveEffects(rawValue: 1 << 4)
    public static let bodyRoll = ActiveEffects(rawValue: 1 << 5)
    public static let refuel = ActiveEffects(rawValue: 1 << 6)
    public static let engineIdle = ActiveEffects(rawValue: 1 << 7)
    public static let engineStop = ActiveEffects(rawValue: 1 << 8)
    public static let roadSurface = ActiveEffects(rawValue: 1 << 9)
    public static let collision = ActiveEffects(rawValue: 1 << 10)
    public static let revLimiter = ActiveEffects(rawValue: 1 << 11)
    public static let warning = ActiveEffects(rawValue: 1 << 12)
    public static let brakeTrigger = ActiveEffects(rawValue: 1 << 13)
    public static let throttleTrigger = ActiveEffects(rawValue: 1 << 14)
    public static let absPulse = ActiveEffects(rawValue: 1 << 15)
    public static let shiftRelease = ActiveEffects(rawValue: 1 << 16)

    public static let names: [(ActiveEffects, String)] = [
        (.brakeTrigger, "Brake trigger"), (.throttleTrigger, "Throttle trigger"), (.absPulse, "ABS pulse (simulated)"),
        (.shiftRelease, "Shift release"),
        (.fineAlert, "Fine alert"), (.gearJolt, "Gear jolt"), (.cranking, "Engine cranking"), (.startLurch, "Start lurch"),
        (.hardBraking, "Hard braking"), (.bodyRoll, "Body roll"), (.refuel, "Refuelling"), (.engineIdle, "Engine vibration"),
        (.engineStop, "Engine stop"), (.roadSurface, "Road surface"), (.collision, "Collision"),
        (.revLimiter, "Rev limiter"), (.warning, "Warning pulse"),
    ]
    public var labels: [String] { Self.names.filter { contains($0.0) }.map(\.1) }
}

public struct EffectEngine {
    /// The engine is stepped at a fixed rate; the Windows mod's timings are expressed in these frames.
    public static let frameInterval = 1.0 / 60.0

    var frame = 0
    var primed = false
    var fineActive = false
    var fineStart = 0.0
    var prevFined = false
    var joltStage = 0
    var shiftStart = -10.0
    var prevGear = 0
    var lurchActive = false
    var lurchStart = 0.0
    var prevEngineEnabled = false
    var prevRpm: Float = 0
    var prevSpeed: Float = 0
    // additions
    var stopStart = -10.0
    var prevWear: Float = 0
    var prevAccel: (Float, Float) = (0, 0)
    var collisionStart = -10.0
    var collisionGain: Float = 0
    var prevDeflection: [Float] = []
    var roadEnvelope: Float = 0
    var prevCritical = false
    var warningStart = -10.0
    var brakeForce = 0.0
    var throttleForce = 0.0

    public init() {}

    /// Seeds the "previous" values so connecting mid-drive doesn't fire spurious events.
    mutating func prime(_ t: TruckState) {
        prevFined = t.fined
        prevGear = t.gear
        prevEngineEnabled = t.engineEnabled
        prevRpm = t.engineRpm
        prevSpeed = t.speed
        prevWear = t.totalWear
        prevAccel = (t.accelX, t.accelZ)
        prevDeflection = t.wheelSuspDeflection
        prevCritical = Self.critical(t, threshold: 0.25)
        primed = true
    }

    /// Forget everything (telemetry lost); the next frame primes again.
    public mutating func reset() { self = EffectEngine() }

    static func critical(_ t: TruckState, threshold: Float) -> Bool {
        t.oilPressureWarning || t.waterTemperatureWarning || t.airPressureWarning || t.wearChassis > threshold
    }

    private struct Mixer {
        var left: Float = 0, right: Float = 0
        let additive: Bool
        mutating func add(left l: Float = 0, right r: Float = 0) {
            if additive { left += l; right += r } else { left = max(left, l); right = max(right, r) }
        }
    }

    private static func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v.isFinite ? v : 0))) }
    private static func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.isFinite ? v : 0))) }

    /// One frame. `now` is monotonic seconds.
    public mutating func step(_ t: TruckState, profile p: Profile, now: Double) -> (output: OutputState, active: ActiveEffects) {
        var o = OutputState()
        var active: ActiveEffects = []
        if !primed { prime(t) }
        defer {
            prevSpeed = t.speed
            prevEngineEnabled = t.engineEnabled
            prevRpm = t.engineRpm
            prevGear = t.gear
            prevFined = t.fined
            prevWear = t.totalWear
            prevAccel = (t.accelX, t.accelZ)
            prevDeflection = t.wheelSuspDeflection
        }
        guard !t.paused else { return (o, active) }

        frame += 1
        let h = p.haptics
        let fuelPct = t.fuelPercent
        let kmh = t.speedKmh
        let accel = (t.speed - prevSpeed) / 0.0166
        var mix = Mixer(additive: h.mix == .additive)

        // ---- lightbar ----
        let L = p.lighting
        var color = RGB.black
        if p.lighting.fineAlert || h.fineAlert.enabled {
            if t.fined != prevFined { fineActive = true; fineStart = now }
        }
        var fineRunning = false
        if fineActive {
            let e = Float(now - fineStart)
            if e > 5 { fineActive = false } else { fineRunning = true }
        }
        if fineRunning {
            active.insert(.fineAlert)
            if h.fineAlert.enabled {
                let v = 200 * h.fineAlert.gain
                if frame % 20 < 10 { mix.add(left: v) } else { mix.add(right: v) }
            }
        }
        if fineRunning && L.fineAlert {
            let phase = Int(Float(now - fineStart) * 4) % 8
            if phase == 0 || phase == 2 { color = RGB(1, 0, 0) } else if phase == 4 || phase == 6 { color = RGB(0, 0, 1) }
        } else if L.parkBrake.enabled && t.parkBrake {
            color = L.parkBrake.color
        } else if L.retarder.enabled && t.engineEnabled && t.retarderLevel != 0 {
            let k = Double((sinf(Float(frame) * 0.1 * Float(t.retarderLevel)) + 1) * 0.5)
            color = RGB(L.retarder.color.r * k, L.retarder.color.g * k, L.retarder.color.b * k)
        } else if L.hazard.enabled && t.engineEnabled && t.blinkerLeftOn && t.blinkerRightOn {
            color = L.hazard.color
        } else if L.blinker.enabled && t.engineEnabled && (t.blinkerLeftOn || t.blinkerRightOn) {
            color = L.blinker.color
        } else if L.lowFuel.enabled && t.fuelWarning {
            let k = Double((sinf(Float(frame) * 0.08) + 1) * 0.5)
            color = RGB(L.lowFuel.color.r * k, L.lowFuel.color.g * k, L.lowFuel.color.b * k)
        } else if L.damage.enabled && max(t.wearChassis, t.wearEngine) > Float(L.damageThreshold) {
            color = L.damage.color
        } else if L.braking.enabled && t.lightBrake {
            let k = 0.3 + 0.7 * Double(max(0, min(1, t.effectiveBrake)))
            color = RGB(L.braking.color.r * k, L.braking.color.g * k, L.braking.color.b * k)
        } else if L.rpmGauge && t.engineEnabled {
            let x = Double(t.rpmFraction)
            color = RGB(min(1, x * 2), min(1, (1 - x) * 2), 0)
        } else if L.base.enabled && t.engineEnabled {
            color = L.base.color
        }
        let bright = max(0, min(1, L.brightness))
        o.red = Self.byte(color.r * 255 * bright)
        o.green = Self.byte(color.g * 255 * bright)
        o.blue = Self.byte(color.b * 255 * bright)

        // ---- mic LED master warning ----
        let critical = Self.critical(t, threshold: 0.25)
        if L.warningsMicLED {
            if critical { o.micLED = .pulse } else if t.adblueWarning || t.batteryVoltageWarning { o.micLED = .on }
        }

        // ---- player LEDs fuel gauge ----
        if L.fuelPlayerLEDs {
            var blinkBelow: Float = -1
            if fuelPct > 80 { o.playerLEDs = 0x1f; blinkBelow = 90 }
            else if fuelPct > 60 { o.playerLEDs = 0x1b; blinkBelow = 70 }
            else if fuelPct > 40 { o.playerLEDs = 0x15; blinkBelow = 50 }
            else if fuelPct > 20 { o.playerLEDs = 0x0a; blinkBelow = 30 }
            else if fuelPct > 0.1 { o.playerLEDs = 0x04; blinkBelow = 10 }
            if fuelPct < blinkBelow { o.playerBrightness = frame % 60 < 30 ? 0 : 2 }
        }

        // ---- refuel chug ----
        if h.refuel.enabled && t.refuel {
            active.insert(.refuel)
            if (frame & 15) < 8 {
                let pct = max(0, min(100, fuelPct))
                let v = h.refuel.gain * (255 - pct * 255 / 100)
                mix.add(left: v, right: v)
            }
        }

        if t.gear != prevGear && t.gear != 0 && prevGear != 0 { shiftStart = now }

        // ---- gear jolt: two frames, strong-left then strong-right ----
        if h.gearJolt.enabled {
            let weak = h.gearJolt.gain * 100, strong = h.gearJolt.gain * 255
            if t.gear != prevGear && t.gear != 0 && prevGear != 0 {
                active.insert(.gearJolt)
                mix.add(left: strong, right: weak)
                joltStage = 2
            } else if joltStage > 0 {
                active.insert(.gearJolt)
                mix.add(left: weak, right: strong)
                joltStage = 0
            }
        }

        // ---- engine start: cranking kick (right) then lurch (left) ----
        if h.engineStart.enabled {
            if t.engineEnabled && !prevEngineEnabled { lurchActive = true; lurchStart = now }
            if !t.engineEnabled && t.engineRpm > 0 && t.engineRpm >= prevRpm {
                active.insert(.cranking)
                if frame % 10 < 5 { mix.add(right: h.engineStart.gain * 200) }
            }
            if lurchActive {
                let e = Float(now - lurchStart)
                if e >= 1.5 { lurchActive = false } else {
                    active.insert(.startLurch)
                    mix.add(left: sinf(e / 1.5 * .pi) * 255 * h.engineStart.gain)
                }
            }
        }

        // ---- engine stop thud (addition) ----
        if h.engineStop.enabled {
            if !t.engineEnabled && prevEngineEnabled { stopStart = now }
            let e = Float(now - stopStart)
            if e >= 0 && e < 0.35 {
                active.insert(.engineStop)
                mix.add(left: (1 - e / 0.35) * 220 * h.engineStop.gain)
            }
        }

        // ---- collision (addition): damage increase, or a horizontal acceleration spike ----
        if h.collision.enabled {
            let wearDelta = t.totalWear - prevWear
            let jerk = hypotf(t.accelX - prevAccel.0, t.accelZ - prevAccel.1)
            var hit: Float = 0
            if wearDelta > 0.0005 { hit = min(1, 0.4 + wearDelta * 20) }
            if jerk > 25 { hit = max(hit, min(1, jerk / 60)) }
            if hit > 0 { collisionStart = now; collisionGain = hit }
            let e = Float(now - collisionStart)
            if e >= 0 && e < 0.4 {
                active.insert(.collision)
                let v = (1 - e / 0.4) * 255 * collisionGain * h.collision.gain
                mix.add(left: v, right: v)
            }
        }

        // ---- warning pulse (addition): three pulses when a critical warning appears ----
        if h.warning.enabled {
            if critical && !prevCritical { warningStart = now }
            let e = now - warningStart
            if e >= 0 && e < 0.9 {
                active.insert(.warning)
                if Int(e / 0.15) % 2 == 0 { mix.add(left: 180 * h.warning.gain, right: 180 * h.warning.gain) }
            }
        }
        prevCritical = critical

        var absPulse = false
        if t.engineEnabled {
            // ---- hard braking, else body roll ----
            let hardBrake = t.inputBrake > 0.8 && kmh > 10 && accel < -10
            if h.hardBraking.enabled && hardBrake {
                active.insert(.hardBraking)
                if frame % 6 < 3 {
                    let v = h.hardBraking.gain * 255
                    mix.add(left: v, right: v)
                }
            } else if h.bodyRoll.enabled && kmh > 10 {
                let roll = t.roll * 100
                var a = Float(abs(roll))
                if a > 0.1 {
                    active.insert(.bodyRoll)
                    a = min(a, 2)
                    let intensity = (a - 0.1) * 225 / 1.9 + 30
                    let v = (sinf(Float(frame) * 0.2) + 1) * 0.5 * intensity * h.bodyRoll.gain
                    if roll <= 0 { mix.add(right: v) } else { mix.add(left: v) }
                }
            }

            // ---- engine vibration (addition): light motor follows RPM ----
            if h.engineIdle.enabled {
                active.insert(.engineIdle)
                mix.add(right: (22 + t.rpmFraction * 50) * h.engineIdle.gain)
            }

            // ---- rev limiter (addition) ----
            if h.revLimiter.enabled && t.engineRpmMax > 0 && t.engineRpm > t.engineRpmMax * 0.95 {
                active.insert(.revLimiter)
                if frame % 4 < 2 { mix.add(right: 200 * h.revLimiter.gain) }
            }

            // ---- road surface (addition): suspension movement, stronger off the tarmac ----
            if h.roadSurface.enabled && kmh > 3 {
                var bump: Float = 0
                if prevDeflection.count == t.wheelSuspDeflection.count {
                    for i in t.wheelSuspDeflection.indices { bump = max(bump, abs(t.wheelSuspDeflection[i] - prevDeflection[i])) }
                }
                var target = min(1, bump / 0.012)
                if t.wheelSubstance.contains(where: Self.isRough) { target = max(target, 0.25 + 0.2 * abs(sinf(Float(frame) * 0.9))) }
                roadEnvelope = max(target, roadEnvelope * 0.85)
                if roadEnvelope > 0.04 {
                    active.insert(.roadSurface)
                    mix.add(left: roadEnvelope * 120 * h.roadSurface.gain, right: roadEnvelope * 255 * h.roadSurface.gain)
                }
            } else {
                roadEnvelope = 0
            }

            // ---- simulated ABS: ETS2 exposes no ABS signal, so wheel slip / hard braking stands in ----
            if p.brake.enabled && p.brake.style == .custom && p.brake.pulse && t.inputBrake > 0.5 && kmh > 10 {
                absPulse = hardBrake || Self.wheelSlip(t)
            }
        }

        // ---- triggers ----
        o.leftTrigger = brakeTrigger(t, p.brake, kmh: kmh, accel: accel, absPulse: absPulse, active: &active)
        o.rightTrigger = throttleTrigger(t, p.throttle, kmh: kmh, now: now, active: &active)

        let master = Float(max(0, min(1, h.master)))
        let cap = Float(max(0, min(1, h.limit))) * 255
        o.rumbleLeft = Self.byte(min(cap, mix.left * master))
        o.rumbleRight = Self.byte(min(cap, mix.right * master))
        return (o, active)
    }

    static func isRough(_ substance: String) -> Bool {
        let s = substance.lowercased()
        return ["dirt", "gravel", "grass", "sand", "snow", "mud", "field", "rumble"].contains { s.contains($0) }
    }

    /// A grounded wheel turning clearly slower than the truck is moving.
    static func wheelSlip(_ t: TruckState) -> Bool {
        let v = abs(t.speed)
        guard v > 3 else { return false }
        for i in 0..<min(t.wheelCount, t.wheelRadius.count, t.wheelAngularVelocity.count, t.wheelOnGround.count)
        where t.wheelOnGround[i] && t.wheelRadius[i] > 0 {
            let wheelSpeed = abs(t.wheelAngularVelocity[i]) * 2 * .pi * t.wheelRadius[i]
            if wheelSpeed < v * 0.7 { return true }
        }
        return false
    }

    private func drive(_ source: TriggerSource, _ t: TruckState, kmh: Float, accel: Float, pedal: Float) -> Double {
        switch source {
        case .speed: return Double(min(1, max(0, abs(kmh) / 90)))
        case .rpm: return Double(t.rpmFraction)
        case .pedal: return Double(min(1, max(0, pedal)))
        case .deceleration: return Double(min(1, max(0, -accel / 8)))
        }
    }

    private func smooth(_ current: Double, toward target: Double, _ smoothing: Double) -> Double {
        current + (target - current) * (1 - 0.95 * max(0, min(1, smoothing)))
    }

    private mutating func brakeTrigger(_ t: TruckState, _ c: TriggerConfig, kmh: Float, accel: Float, absPulse: Bool,
                                       active: inout ActiveEffects) -> TriggerEffect {
        guard c.enabled, c.intensity > 0, t.engineEnabled else { brakeForce = 0; return .off }
        let effect: TriggerEffect
        switch c.style {
        case .original:
            // Resistance grows with speed, maximum at 90 km/h.
            let k = max(0, min(90, kmh))
            effect = .continuous(start: 0, force: Self.byte(k * 200 / 90 * Float(c.intensity)))
        case .custom:
            if absPulse {
                active.insert(.absPulse)
                let amp = UInt8(max(1, min(8, (c.pulseStrength * 8).rounded())))
                return .vibration(zones: [UInt8](repeating: amp, count: 10), frequency: Self.byte(c.pulseFrequency))
            }
            let x = c.curve.value(at: drive(c.source, t, kmh: kmh, accel: accel, pedal: t.effectiveBrake))
            let target = (c.minForce + (c.maxForce - c.minForce) * x) * c.intensity
            brakeForce = smooth(brakeForce, toward: target, c.smoothing)
            effect = .continuous(start: Self.byte(c.deadZone * 255), force: Self.byte((brakeForce * 255).rounded()))
        }
        if effect != .off { active.insert(.brakeTrigger) }
        return effect
    }

    private mutating func throttleTrigger(_ t: TruckState, _ c: TriggerConfig, kmh: Float, now: Double,
                                          active: inout ActiveEffects) -> TriggerEffect {
        guard c.enabled, c.intensity > 0, t.engineEnabled else { throttleForce = 0; return .off }
        // Mid-shift the drive is interrupted: the pedal goes slack, then resistance builds back.
        if c.shiftRelease && now - shiftStart >= 0 && now - shiftStart < c.shiftReleaseTime {
            active.insert(.shiftRelease)
            throttleForce = 0
            return .off
        }
        switch c.style {
        case .original:
            // Vibration frequency is high when lugging or near the redline, calm in between.
            // (The Windows mod fixes these thresholds at startup; here they follow the current truck.)
            let span = t.engineRpmMax - 550
            let low = span * 0.2 + 550
            let high = span * 0.7 + 550
            let rpm = t.engineRpm
            var v: Float
            if rpm > low {
                if rpm < high || t.engineRpmMax == high { v = 0 } else {
                    let x = min(max(rpm, high), t.engineRpmMax)
                    v = (x - high) * 255 / (t.engineRpmMax - high)
                }
            } else if low == 550 {
                v = 200
            } else {
                let x = min(max(rpm, 550), low)
                v = 200 - (x - 550) * 200 / (low - 550)
            }
            active.insert(.throttleTrigger)
            return .effectEx(start: 0, keepEffect: true, beginForce: 0, middleForce: 0, endForce: 0,
                             frequency: Self.byte(Float(c.intensity) * v))
        case .custom:
            if c.pulse && t.engineRpmMax > 0 && t.engineRpm > t.engineRpmMax * 0.95 {
                active.insert(.throttleTrigger)
                let amp = UInt8(max(1, min(8, (c.pulseStrength * 8).rounded())))
                return .vibration(zones: [UInt8](repeating: amp, count: 10), frequency: Self.byte(c.pulseFrequency))
            }
            let x = c.curve.value(at: drive(c.source, t, kmh: kmh, accel: 0, pedal: t.effectiveThrottle))
            let target = (c.minForce + (c.maxForce - c.minForce) * x) * c.intensity
            throttleForce = smooth(throttleForce, toward: target, c.smoothing)
            let effect = TriggerEffect.continuous(start: Self.byte(c.deadZone * 255), force: Self.byte((throttleForce * 255).rounded()))
            if effect != .off { active.insert(.throttleTrigger) }
            return effect
        }
    }
}

/// Rim steering from the Windows mod: rotate the left stick around its rim like a steering wheel.
public struct RimSteering {
    var active = false
    var prevAngle = 0.0
    public private(set) var steer = 0.0 // radians, clamped to +-lock

    public init() {}

    /// One stick sample (x right-positive, y up-positive, -128...127). Returns normalized steering in [-1, 1].
    public mutating func step(x: Int, y: Int, speedMs: Float, config c: RimConfig) -> Double {
        let lock = c.lockDegrees * 2 * .pi / 360
        let threshold = active ? 86.36 : 99.06
        if Double(x * x + y * y) >= threshold * threshold {
            let angle = atan2(Double(x), Double(y))
            if active {
                var kmh = abs(Double(speedMs * 3.6))
                if !kmh.isFinite { kmh = 0 }
                let ratio = min(1, kmh / c.maxDeviationSpeed)
                let delta = remainder(angle - prevAngle, 2 * .pi)
                steer += delta / (ratio * (c.maxDegreeDeviation - 1) + 1)
                steer = max(-lock, min(lock, steer))
            }
            active = true
            prevAngle = angle
        } else {
            active = false
        }
        return steer / lock
    }
}
