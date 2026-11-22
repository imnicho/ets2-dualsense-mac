import Foundation

/// Response curve through five evenly spaced points (x = 0, 0.25, 0.5, 0.75, 1), linearly interpolated.
public struct Curve: Codable, Equatable, Sendable {
    public var points: [Double]

    public init(_ points: [Double]) { self.points = points }

    public static let linear = Curve([0, 0.25, 0.5, 0.75, 1])
    public static let progressive = Curve([0, 0.06, 0.25, 0.56, 1])
    public static let aggressive = Curve([0, 0.5, 0.75, 0.9, 1])
    public static let sCurve = Curve([0, 0.1, 0.5, 0.9, 1])
    public static let flat = Curve([1, 1, 1, 1, 1])
    public static let presets: [(String, Curve)] = [
        ("Linear", .linear), ("Progressive", .progressive), ("Aggressive", .aggressive), ("S-Curve", .sCurve), ("Flat", .flat),
    ]

    public func value(at x: Double) -> Double {
        guard points.count >= 2 else { return points.first ?? 0 }
        let c = min(1, max(0, x.isFinite ? x : 0)) * Double(points.count - 1)
        let i = min(points.count - 2, Int(c))
        let f = c - Double(i)
        return min(1, max(0, points[i] + (points[i + 1] - points[i]) * f))
    }
}

public enum TriggerStyle: String, Codable, CaseIterable, Sendable {
    case original   // behaviour of the Windows mod
    case custom     // curve-driven resistance
}

public enum TriggerSource: String, Codable, CaseIterable, Sendable {
    case speed, rpm, pedal, deceleration

    public var label: String {
        switch self {
        case .speed: return "Vehicle speed"
        case .rpm: return "Engine RPM"
        case .pedal: return "Pedal pressure (game)"
        case .deceleration: return "Deceleration"
        }
    }
}

public struct TriggerConfig: Codable, Equatable, Sendable {
    public var enabled = true
    public var style: TriggerStyle = .original
    public var intensity = 1.0          // 0...1 overall scale
    public var source: TriggerSource = .speed
    public var minForce = 0.0           // 0...1
    public var maxForce = 0.8
    public var curve: Curve = .linear
    public var deadZone = 0.0           // 0...1 of trigger travel before resistance starts
    public var smoothing = 0.3          // 0...1
    public var pulse = false            // brake: simulated ABS pulse; throttle: rev-limit buzz
    public var pulseStrength = 0.6
    public var pulseFrequency = 25.0    // Hz
    public var shiftRelease = false     // throttle: resistance drops away while a gear change is in progress
    public var shiftReleaseTime = 0.3   // seconds

    public init() {}

    // Decoded key by key so profiles saved before a setting existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T { try c.decodeIfPresent(T.self, forKey: key) ?? fallback }
        enabled = try get(.enabled, enabled)
        style = try get(.style, style)
        intensity = try get(.intensity, intensity)
        source = try get(.source, source)
        minForce = try get(.minForce, minForce)
        maxForce = try get(.maxForce, maxForce)
        curve = try get(.curve, curve)
        deadZone = try get(.deadZone, deadZone)
        smoothing = try get(.smoothing, smoothing)
        pulse = try get(.pulse, pulse)
        pulseStrength = try get(.pulseStrength, pulseStrength)
        pulseFrequency = try get(.pulseFrequency, pulseFrequency)
        shiftRelease = try get(.shiftRelease, shiftRelease)
        shiftReleaseTime = try get(.shiftReleaseTime, shiftReleaseTime)
    }
}

public struct HapticEffect: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var intensity: Double        // 0...1
    public init(_ enabled: Bool, _ intensity: Double = 1) { self.enabled = enabled; self.intensity = intensity }
    var gain: Float { enabled ? Float(max(0, min(1, intensity))) : 0 }
}

public enum MixMode: String, Codable, CaseIterable, Sendable {
    case strongest  // highest effect wins per motor (Windows mod behaviour)
    case additive   // effects add up, clamped
}

public struct HapticsConfig: Codable, Equatable, Sendable {
    // From the Windows mod.
    public var engineStart = HapticEffect(true)
    public var gearJolt = HapticEffect(true)
    public var hardBraking = HapticEffect(true)
    public var bodyRoll = HapticEffect(true)
    public var refuel = HapticEffect(true)
    public var fineAlert = HapticEffect(true)
    // Additions.
    public var engineIdle = HapticEffect(false, 0.5)
    public var engineStop = HapticEffect(false, 0.7)
    public var roadSurface = HapticEffect(false, 0.6)
    public var collision = HapticEffect(false, 1)
    public var revLimiter = HapticEffect(false, 0.5)
    public var warning = HapticEffect(false, 0.8)

    public var mix: MixMode = .strongest
    public var master = 1.0             // 0...1
    public var limit = 1.0              // hard cap on motor output, 0...1

    public init() {}
}

public struct RGB: Codable, Equatable, Sendable {
    public var r: Double, g: Double, b: Double   // 0...1
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public static let black = RGB(0, 0, 0)
}

public struct LightRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var color: RGB
    public init(_ enabled: Bool, _ color: RGB) { self.enabled = enabled; self.color = color }
}

public struct LightingConfig: Codable, Equatable, Sendable {
    // Highest priority first; the first rule that applies sets the lightbar.
    public var fineAlert = true                                   // red/blue flash, 5 s
    public var parkBrake = LightRule(true, RGB(1, 0, 0))
    public var retarder = LightRule(true, RGB(0, 0, 1))           // pulses faster with retarder level
    public var hazard = LightRule(true, RGB(1, 1, 0))
    public var blinker = LightRule(true, RGB(0, 1, 0))
    public var lowFuel = LightRule(false, RGB(1, 0.35, 0))
    public var damage = LightRule(false, RGB(1, 0, 0.6))
    public var damageThreshold = 0.25
    public var braking = LightRule(false, RGB(1, 0, 0))
    public var rpmGauge = false                                   // green to red with engine speed
    public var base = LightRule(false, RGB(0.1, 0.3, 1))          // engine running, nothing else active
    public var brightness = 1.0

    public var fuelPlayerLEDs = true
    public var blinkerPlayerLEDs = false                          // left signal on the left LEDs, right on the right
    public var warningsMicLED = true

    public init() {}
}

public struct RimConfig: Codable, Equatable, Sendable {
    public var enabled = false
    public var lockDegrees = 450.0
    public var maxDegreeDeviation = 5.0
    public var maxDeviationSpeed = 90.0
    public init() {}
}

public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var builtIn = false
    /// Auto-select this profile when the truck brand/name/id contains this text (empty = never).
    public var truckMatch = ""
    public var throttle = TriggerConfig()
    public var brake = TriggerConfig()
    public var haptics = HapticsConfig()
    public var lighting = LightingConfig()
    public var rim = RimConfig()

    public init(name: String) { self.name = name }

    public func matches(_ t: TruckState) -> Bool {
        let needle = truckMatch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return false }
        return "\(t.truckBrand) \(t.truckName) \(t.truckId)".lowercased().contains(needle)
    }
}

extension Profile {
    private static func builtin(_ name: String, _ uuid: String, _ edit: (inout Profile) -> Void) -> Profile {
        var p = Profile(name: name)
        p.id = UUID(uuidString: uuid)!
        p.builtIn = true
        p.throttle.source = .rpm
        edit(&p)
        return p
    }

    /// Same behaviour and defaults as the Windows mod.
    public static let original = builtin("Classic", "00000000-0000-4000-8000-000000000001") { _ in }

    public static let realistic = builtin("Realistic Trucking", "00000000-0000-4000-8000-000000000002") { p in
        p.brake.style = .custom; p.brake.source = .pedal
        p.brake.minForce = 0.15; p.brake.maxForce = 0.75; p.brake.curve = .progressive; p.brake.pulse = true
        p.throttle.style = .custom; p.throttle.source = .rpm
        p.throttle.minForce = 0.05; p.throttle.maxForce = 0.45; p.throttle.curve = .sCurve
        p.throttle.shiftRelease = true
        p.haptics.engineIdle = HapticEffect(true, 0.25)
        p.haptics.roadSurface = HapticEffect(true, 0.5)
        p.haptics.collision = HapticEffect(true, 1)
        p.haptics.engineStop = HapticEffect(true, 0.6)
        p.haptics.bodyRoll.intensity = 0.6
        p.lighting.lowFuel.enabled = true
        p.lighting.blinkerPlayerLEDs = true
    }

    public static let immersive = builtin("Immersive", "00000000-0000-4000-8000-000000000003") { p in
        p.brake.style = .custom; p.brake.source = .speed
        p.brake.minForce = 0.2; p.brake.maxForce = 1; p.brake.curve = .aggressive; p.brake.pulse = true; p.brake.pulseStrength = 0.9
        p.throttle.style = .custom; p.throttle.source = .rpm
        p.throttle.minForce = 0.1; p.throttle.maxForce = 0.7; p.throttle.pulse = true
        p.throttle.shiftRelease = true; p.throttle.shiftReleaseTime = 0.4
        p.haptics.engineIdle = HapticEffect(true, 0.5)
        p.haptics.roadSurface = HapticEffect(true, 0.9)
        p.haptics.collision = HapticEffect(true, 1)
        p.haptics.engineStop = HapticEffect(true, 1)
        p.haptics.revLimiter = HapticEffect(true, 0.7)
        p.haptics.warning = HapticEffect(true, 1)
        p.haptics.mix = .additive
        p.lighting.lowFuel.enabled = true; p.lighting.damage.enabled = true
        p.lighting.blinkerPlayerLEDs = true
        p.lighting.braking.enabled = true; p.lighting.rpmGauge = true
    }

    public static let arcade = builtin("Arcade", "00000000-0000-4000-8000-000000000004") { p in
        p.brake.style = .custom; p.brake.source = .speed
        p.brake.minForce = 0; p.brake.maxForce = 0.4; p.brake.smoothing = 0.1
        p.throttle.intensity = 0.6
        p.haptics.collision = HapticEffect(true, 1)
        p.haptics.revLimiter = HapticEffect(true, 0.8)
        p.haptics.bodyRoll.enabled = false
        p.haptics.mix = .additive
        p.lighting.rpmGauge = true
    }

    public static let subtle = builtin("Subtle", "00000000-0000-4000-8000-000000000005") { p in
        p.brake.intensity = 0.4
        p.throttle.intensity = 0.3
        p.haptics.master = 0.4
        p.haptics.bodyRoll.enabled = false
        p.haptics.limit = 0.6
        p.lighting.brightness = 0.4
    }

    public static let builtIns: [Profile] = [.original, .realistic, .immersive, .arcade, .subtle]
}

/// Loads and saves profiles as one JSON file.
public final class ProfileStore {
    public struct Document: Codable, Equatable {
        public var selected: UUID
        public var custom: [Profile]
        public init(selected: UUID, custom: [Profile]) { self.selected = selected; self.custom = custom }
    }

    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ETS2DualSense/profiles.json")
    }

    public func load() -> Document {
        if let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let selected = (object["selected"] as? String).flatMap(UUID.init(uuidString:)),
           let custom = object["custom"] as? [Any] {
            return Document(selected: selected, custom: custom.compactMap { try? Self.profile(fromJSON: $0) })
        }
        return Document(selected: Profile.original.id, custom: [])
    }

    /// Decodes a profile, filling any setting the file lacks with its default, so files written
    /// by older versions keep loading.
    static func profile(fromJSON object: Any) throws -> Profile {
        let defaults = try JSONSerialization.jsonObject(with: encoder.encode(Profile(name: "")))
        func merge(_ base: Any, _ over: Any) -> Any {
            guard let b = base as? [String: Any], let o = over as? [String: Any] else { return over }
            return b.merging(o) { merge($0, $1) }
        }
        return try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: merge(defaults, object)))
    }

    public func save(_ doc: Document) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(doc).write(to: url, options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static func export(_ profile: Profile) throws -> Data { try encoder.encode(profile) }

    /// Imported profiles always become new custom profiles.
    public static func importProfile(_ data: Data) throws -> Profile {
        var p = try profile(fromJSON: JSONSerialization.jsonObject(with: data))
        p.id = UUID()
        p.builtIn = false
        return p
    }
}
