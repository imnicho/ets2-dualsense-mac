import CTelemetry
import Foundation

/// Application-level view of one telemetry frame.
public struct TruckState: Codable, Equatable, Sendable {
    public var paused = true
    public var game = 0                 // 1 = ETS2, 2 = ATS
    public var engineEnabled = false
    public var electricEnabled = false
    public var parkBrake = false
    public var motorBrake = false
    public var airPressureWarning = false
    public var airPressureEmergency = false
    public var fuelWarning = false
    public var adblueWarning = false
    public var oilPressureWarning = false
    public var waterTemperatureWarning = false
    public var batteryVoltageWarning = false
    public var blinkerLeftOn = false
    public var blinkerRightOn = false
    public var hazardWarning = false
    public var lightBrake = false
    public var lightReverse = false
    public var trailerConnected = false
    public var refuel = false
    public var fined = false
    public var tollgate = false

    public var gear = 0
    public var displayedGear = 0
    public var retarderLevel = 0
    public var retarderSteps = 0

    public var speed: Float = 0         // m/s
    public var cruiseControl: Float = 0
    public var engineRpm: Float = 0
    public var engineRpmMax: Float = 0
    public var inputThrottle: Float = 0
    public var effectiveThrottle: Float = 0
    public var inputBrake: Float = 0
    public var effectiveBrake: Float = 0
    public var inputSteering: Float = 0
    public var fuel: Float = 0
    public var fuelCapacity: Float = 0
    public var airPressure: Float = 0
    public var brakeTemperature: Float = 0
    public var wearEngine: Float = 0
    public var wearTransmission: Float = 0
    public var wearCabin: Float = 0
    public var wearChassis: Float = 0
    public var wearWheels: Float = 0
    public var trailerWearChassis: Float = 0
    public var cargoDamage: Float = 0
    public var cargoMass: Float = 0
    public var accelX: Float = 0, accelY: Float = 0, accelZ: Float = 0
    public var roll: Double = 0         // 1.0 = full turn
    public var pitch: Double = 0

    public var wheelCount = 0
    public var wheelSuspDeflection: [Float] = []
    public var wheelAngularVelocity: [Float] = []
    public var wheelRadius: [Float] = []
    public var wheelOnGround: [Bool] = []
    public var wheelSubstance: [String] = []

    public var truckBrand = ""
    public var truckName = ""
    public var truckId = ""

    public init() {}

    public var speedKmh: Float { speed * 3.6 }
    public var fuelPercent: Float { fuelCapacity > 0 ? fuel / fuelCapacity * 100 : 0 }
    public var rpmFraction: Float { engineRpmMax > 0 ? min(1, max(0, engineRpm / engineRpmMax)) : 0 }
    public var totalWear: Float {
        wearEngine + wearTransmission + wearCabin + wearChassis + wearWheels + trailerWearChassis + cargoDamage
    }
    public var gearLabel: String {
        gear == 0 ? "N" : (gear < 0 ? "R\(-gear)" : "\(gear)")
    }
}

extension TruckState {
    init(_ t: Telemetry) {
        self.init()
        paused = t.paused != 0
        game = Int(t.game)
        engineEnabled = t.engineEnabled != 0
        electricEnabled = t.electricEnabled != 0
        parkBrake = t.parkBrake != 0
        motorBrake = t.motorBrake != 0
        airPressureWarning = t.airPressureWarning != 0
        airPressureEmergency = t.airPressureEmergency != 0
        fuelWarning = t.fuelWarning != 0
        adblueWarning = t.adblueWarning != 0
        oilPressureWarning = t.oilPressureWarning != 0
        waterTemperatureWarning = t.waterTemperatureWarning != 0
        batteryVoltageWarning = t.batteryVoltageWarning != 0
        blinkerLeftOn = t.blinkerLeftOn != 0
        blinkerRightOn = t.blinkerRightOn != 0
        hazardWarning = t.hazardWarning != 0
        lightBrake = t.lightBrake != 0
        lightReverse = t.lightReverse != 0
        trailerConnected = t.trailerConnected != 0
        refuel = t.refuel != 0
        fined = t.fined != 0
        tollgate = t.tollgate != 0
        gear = Int(t.gear)
        displayedGear = Int(t.displayedGear)
        retarderLevel = Int(t.retarderLevel)
        retarderSteps = Int(t.retarderSteps)
        speed = t.speed
        cruiseControl = t.cruiseControl
        engineRpm = t.engineRpm
        engineRpmMax = t.engineRpmMax
        inputThrottle = t.inputThrottle
        effectiveThrottle = t.effectiveThrottle
        inputBrake = t.inputBrake
        effectiveBrake = t.effectiveBrake
        inputSteering = t.inputSteering
        fuel = t.fuel
        fuelCapacity = t.fuelCapacity
        airPressure = t.airPressure
        brakeTemperature = t.brakeTemperature
        wearEngine = t.wearEngine
        wearTransmission = t.wearTransmission
        wearCabin = t.wearCabin
        wearChassis = t.wearChassis
        wearWheels = t.wearWheels
        trailerWearChassis = t.trailerWearChassis
        cargoDamage = t.cargoDamage
        cargoMass = t.cargoMass
        accelX = t.accelX; accelY = t.accelY; accelZ = t.accelZ
        roll = t.roll
        pitch = t.pitch

        let n = min(Int(t.wheelCount), Int(ETS2DS_MAX_WHEELS))
        wheelCount = n
        func floats<T>(_ v: T) -> [Float] { withUnsafeBytes(of: v) { Array($0.bindMemory(to: Float.self).prefix(n)) } }
        func string<T>(_ v: T) -> String {
            withUnsafeBytes(of: v) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }
        wheelSuspDeflection = floats(t.wheelSuspDeflection)
        wheelAngularVelocity = floats(t.wheelAngularVelocity)
        wheelRadius = floats(t.wheelRadius)
        wheelOnGround = withUnsafeBytes(of: t.wheelOnGround) { $0.prefix(n).map { $0 != 0 } }
        let indices = withUnsafeBytes(of: t.wheelSubstance) { Array($0.bindMemory(to: UInt32.self).prefix(n)) }
        wheelSubstance = withUnsafeBytes(of: t.substances) { raw in
            indices.map { i -> String in
                guard i < UInt32(ETS2DS_MAX_SUBSTANCES) else { return "" }
                let slot = UnsafeRawBufferPointer(rebasing: raw[Int(i) * 32..<Int(i) * 32 + 32])
                return String(decoding: slot.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        truckBrand = string(t.truckBrand)
        truckName = string(t.truckName)
        truckId = string(t.truckId)
    }
}

public struct TelemetrySample: Sendable {
    public var truck: TruckState
    public var sdkActive: Bool
    /// Milliseconds since the plugin last published a frame.
    public var ageMs: Double
    public var frameSeq: UInt32
}

/// Reads the plugin's memory-mapped telemetry file.
public final class TelemetryReader {
    private let path: String
    private var ptr: UnsafeMutablePointer<Telemetry>?
    private var lastOpenAttempt: UInt64 = 0

    public init(path: String = ETS2DS_TELEMETRY_PATH) { self.path = path }
    deinit { close() }

    public static var defaultPath: String { ETS2DS_TELEMETRY_PATH }
    public static func nowMs() -> UInt64 { ets2ds_now_ms() }

    private func open() {
        let now = ets2ds_now_ms()
        guard now &- lastOpenAttempt > 1000 || lastOpenAttempt == 0 else { return }
        lastOpenAttempt = now
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, Int(st.st_size) >= MemoryLayout<Telemetry>.size else { return }
        let p = mmap(nil, MemoryLayout<Telemetry>.size, PROT_READ, MAP_SHARED, fd, 0)
        guard p != MAP_FAILED, let p else { return }
        ptr = p.bindMemory(to: Telemetry.self, capacity: 1)
    }

    private func close() {
        if let ptr { munmap(ptr, MemoryLayout<Telemetry>.size) }
        ptr = nil
    }

    /// Returns nil when the plugin has never run (no file) or the file is not ours.
    public func read() -> TelemetrySample? {
        if ptr == nil { open() }
        guard let ptr else { return nil }
        var copy = Telemetry()
        for _ in 0..<8 {
            let before = ptr.pointee.seq
            if before & 1 != 0 { continue }
            copy = ptr.pointee
            if ptr.pointee.seq == before { break }
        }
        guard copy.magic == ETS2DS_MAGIC else {
            close() // stale or replaced file: map it again on a later call
            return nil
        }
        let now = ets2ds_now_ms()
        let age = now >= copy.heartbeatMs ? Double(now - copy.heartbeatMs) : 0
        if age > 5000, now &- lastOpenAttempt > 2000 {
            // The file may have been recreated (e.g. /tmp cleaned): map it again.
            close()
            lastOpenAttempt = 0
            open()
        }
        return TelemetrySample(truck: TruckState(copy), sdkActive: copy.sdkActive != 0, ageMs: age, frameSeq: copy.seq)
    }
}

/// Publishes the rim-steering value the plugin's input device reads.
public final class SteeringWriter {
    private var ptr: UnsafeMutablePointer<UInt64>?

    public init() {}
    deinit { if let ptr { ptr.pointee = 0; munmap(ptr, 8) } }

    public func write(_ normalized: Double) {
        if ptr == nil {
            let fd = Darwin.open(ETS2DS_STEERING_PATH, O_RDWR | O_CREAT, 0o666)
            guard fd >= 0 else { return }
            defer { Darwin.close(fd) }
            fchmod(fd, 0o666)
            guard ftruncate(fd, 8) == 0 else { return }
            let p = mmap(nil, 8, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
            guard p != MAP_FAILED, let p else { return }
            ptr = p.bindMemory(to: UInt64.self, capacity: 1)
        }
        ptr?.pointee = ets2ds_steer_pack(normalized)
    }

    public func stop() { ptr?.pointee = 0 }
}
