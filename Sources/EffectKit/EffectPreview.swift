import Foundation

/// Short scripted telemetry clips that make one effect fire, for the "Preview" buttons.
public enum EffectPreview: String, CaseIterable, Sendable {
    case engineStart, gearJolt, hardBraking, bodyRoll, refuel, fineAlert
    case engineIdle, engineStop, roadSurface, collision, revLimiter, warning
    case parkBrake, retarder, hazard, blinker, lowFuel, damage, braking, rpmGauge, base, fuelGauge

    public var duration: Double {
        switch self {
        case .engineStart: return 2.4
        case .gearJolt: return 0.4
        case .fineAlert: return 5.1
        case .engineStop, .collision: return 0.8
        case .warning, .hardBraking: return 1.3
        case .fuelGauge: return 5
        default: return 2.5
        }
    }

    /// Telemetry `e` seconds into the clip.
    public func truck(at e: Double) -> TruckState {
        var t = TruckState()
        t.paused = false
        t.engineEnabled = true
        t.engineRpmMax = 2500
        t.engineRpm = 1300
        t.fuelCapacity = 1000
        t.fuel = 1000
        t.gear = 4
        switch self {
        case .engineStart:
            t.engineEnabled = e > 0.7
            t.engineRpm = e > 0.7 ? 600 : Float(e) * 800
        case .gearJolt:
            t.gear = e < 0.1 ? 3 : 4
        case .hardBraking:
            t.speed = max(0, 25 - Float(e) * 11)
            t.inputBrake = 1; t.effectiveBrake = 1; t.lightBrake = true
        case .bodyRoll:
            t.speed = 20
            t.roll = sin(e * 3) * 0.015
        case .refuel:
            t.refuel = true
            t.fuel = 300 + Float(e) * 100
        case .fineAlert:
            t.fined = e > 0.05
        case .engineIdle:
            t.engineRpm = 600 + Float(e / duration) * 1700
        case .engineStop:
            t.engineEnabled = e < 0.2
        case .roadSurface:
            t.speed = 15
            t.wheelCount = 2
            t.wheelSubstance = ["gravel", "gravel"]
            t.wheelSuspDeflection = [Float(sin(e * 45)) * 0.01, Float(cos(e * 38)) * 0.01]
        case .collision:
            t.wearChassis = e > 0.1 ? 0.03 : 0
        case .revLimiter:
            t.engineRpm = 2480
        case .warning:
            t.oilPressureWarning = e > 0.1
        case .parkBrake:
            t.parkBrake = true
        case .retarder:
            t.retarderLevel = 2
        case .hazard:
            t.blinkerLeftOn = Int(e * 2.5) % 2 == 0; t.blinkerRightOn = t.blinkerLeftOn; t.hazardWarning = true
        case .blinker:
            t.blinkerLeftOn = Int(e * 2.5) % 2 == 0
        case .lowFuel:
            t.fuel = 80; t.fuelWarning = true
        case .damage:
            t.wearChassis = 0.9
        case .braking:
            t.lightBrake = true
            t.effectiveBrake = Float(min(1, e / 1.5))
        case .rpmGauge:
            t.engineRpm = Float(e / duration) * 2500
        case .base:
            break
        case .fuelGauge:
            t.fuel = 1000 * Float(1 - e / duration)
        }
        return t
    }

    /// The profile with this effect forced on, so a disabled effect can still be previewed.
    public func enabling(in profile: Profile) -> Profile {
        var p = profile
        func on(_ e: inout HapticEffect) { e.enabled = true }
        switch self {
        case .engineStart: on(&p.haptics.engineStart)
        case .gearJolt: on(&p.haptics.gearJolt)
        case .hardBraking: on(&p.haptics.hardBraking)
        case .bodyRoll: on(&p.haptics.bodyRoll)
        case .refuel: on(&p.haptics.refuel)
        case .fineAlert: on(&p.haptics.fineAlert)
        case .engineIdle: on(&p.haptics.engineIdle)
        case .engineStop: on(&p.haptics.engineStop)
        case .roadSurface: on(&p.haptics.roadSurface)
        case .collision: on(&p.haptics.collision)
        case .revLimiter: on(&p.haptics.revLimiter)
        case .warning: on(&p.haptics.warning)
        case .parkBrake: p.lighting.parkBrake.enabled = true
        case .retarder: p.lighting.retarder.enabled = true
        case .hazard: p.lighting.hazard.enabled = true
        case .blinker: p.lighting.blinker.enabled = true
        case .lowFuel: p.lighting.lowFuel.enabled = true
        case .damage: p.lighting.damage.enabled = true
        case .braking: p.lighting.braking.enabled = true
        case .rpmGauge: p.lighting.rpmGauge = true
        case .base: p.lighting.base.enabled = true
        case .fuelGauge: p.lighting.fuelPlayerLEDs = true
        }
        // Lighting previews should show their own rule, not a higher-priority one.
        switch self {
        case .lowFuel, .damage, .braking, .rpmGauge, .base:
            p.lighting.parkBrake.enabled = false; p.lighting.retarder.enabled = false
            p.lighting.hazard.enabled = false; p.lighting.blinker.enabled = false
            if self != .lowFuel { p.lighting.lowFuel.enabled = false }
            if self == .braking || self == .rpmGauge || self == .base { p.lighting.damage.enabled = false }
            if self == .rpmGauge || self == .base { p.lighting.braking.enabled = false }
            if self == .base { p.lighting.rpmGauge = false }
        default: break
        }
        return p
    }
}
