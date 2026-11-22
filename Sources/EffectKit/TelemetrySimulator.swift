import Foundation

/// A scripted 44-second drive used for demo mode and tests: crank, pull away through the gears,
/// cruise with indicators, brake hard, park, refuel, switch off.
public struct TelemetrySimulator {
    public static let cycle = 44.0
    public private(set) var time = 0.0
    var speed: Float = 0
    var fuel: Float = 300
    var fined = false

    public init() {}

    public mutating func step(dt: Double = EffectEngine.frameInterval) -> TruckState {
        let previous = time.truncatingRemainder(dividingBy: Self.cycle)
        time += dt
        let s = time.truncatingRemainder(dividingBy: Self.cycle)
        if s < previous { speed = 0; fuel = 300 }

        var t = TruckState()
        t.paused = false
        t.game = 1
        t.electricEnabled = s < 42
        t.engineRpmMax = 2500
        t.fuelCapacity = 1000
        t.truckBrand = "Simulated"
        t.truckName = "Demo Truck"
        t.truckId = "vehicle.demo"
        t.wheelCount = 4
        t.wheelRadius = [0.5, 0.5, 0.5, 0.5]
        t.wheelOnGround = [true, true, true, true]
        t.wheelSubstance = [String](repeating: s > 18 && s < 20 ? "gravel" : "road", count: 4)
        t.retarderSteps = 3

        var accel: Float = 0
        switch s {
        case ..<1:
            break
        case ..<2:
            t.engineRpm = Float(s - 1) * 600
        case ..<4:
            t.engineEnabled = true
            t.parkBrake = s < 3.5
        case ..<20:
            t.engineEnabled = true
            t.inputThrottle = 0.85
            accel = speed < 25 ? 1.8 : 0
        case ..<24:
            t.engineEnabled = true
            t.inputThrottle = 0.3
            t.blinkerLeftOn = Int(s * 2) % 2 == 0
            t.roll = sin((s - 20) * 1.5) * 0.012
            t.retarderLevel = s > 23 ? 2 : 0
        case ..<27:
            t.engineEnabled = true
            t.inputBrake = 1
            t.lightBrake = true
            accel = speed > 0 ? -11 : 0
        case ..<32:
            t.engineEnabled = true
            t.parkBrake = true
            t.blinkerLeftOn = Int(s * 2) % 2 == 0
            t.blinkerRightOn = t.blinkerLeftOn
            t.hazardWarning = true
        case ..<38:
            t.engineEnabled = true
            t.parkBrake = true
            fuel = min(1000, fuel + Float(dt) * 110)
            t.refuel = true
        case ..<42:
            t.engineEnabled = true
            t.parkBrake = true
        default:
            break
        }
        if s >= 30 && previous < 30 { fined.toggle() }
        t.fined = fined

        speed = max(0, speed + accel * Float(dt))
        t.speed = speed
        t.effectiveThrottle = t.inputThrottle
        t.effectiveBrake = t.inputBrake
        t.accelZ = -accel
        t.fuel = fuel
        t.fuelWarning = fuel < 150

        if t.engineEnabled {
            // 6 evenly spaced gears up to 25 m/s; RPM sweeps 1000...1900 within each.
            let band: Float = 25.0 / 6
            let g = min(5, Int(speed / band))
            t.gear = speed < 0.1 && t.inputThrottle == 0 ? 0 : g + 1
            let within = (speed - Float(g) * band) / band
            t.engineRpm = t.gear == 0 ? 600 : 1000 + within * 900
        }
        t.displayedGear = t.gear
        let wheel = speed / (2 * .pi * 0.5)
        let bump = Float(sin(time * 40)) * (t.wheelSubstance[0] == "gravel" ? 0.01 : 0.0005) * (speed > 1 ? 1 : 0)
        t.wheelAngularVelocity = [wheel, wheel, wheel, wheel]
        t.wheelSuspDeflection = [bump, -bump, bump, -bump]
        return t
    }
}
