import Foundation

public enum Transport: String, Sendable, Codable {
    case usb = "USB"
    case bluetooth = "Bluetooth"
}

/// One adaptive-trigger effect: the raw mode byte plus its 10 parameter bytes,
/// exactly as they are placed in the output report.
public struct TriggerEffect: Equatable, Sendable {
    public var mode: UInt8
    public var params: [UInt8]

    public init(mode: UInt8, params: [UInt8] = []) {
        self.mode = mode
        self.params = Array((params + [UInt8](repeating: 0, count: 10)).prefix(10))
    }

    public static let off = TriggerEffect(mode: 0x05)

    /// Constant resistance from `start` (0-255 travel) with `force` (0-255). DS5W "ContinuousResistance".
    public static func continuous(start: UInt8, force: UInt8) -> TriggerEffect {
        force == 0 ? .off : TriggerEffect(mode: 0x01, params: [start, force])
    }

    /// Resistance only between `start` and `end` (0-255 travel). DS5W "SectionResistance".
    public static func section(start: UInt8, end: UInt8, force: UInt8) -> TriggerEffect {
        force == 0 ? .off : TriggerEffect(mode: 0x02, params: [start, end, force])
    }

    /// DS5W "EffectEx": vibration at `frequency` with three force stages.
    public static func effectEx(start: UInt8, keepEffect: Bool, beginForce: UInt8, middleForce: UInt8,
                                endForce: UInt8, frequency: UInt8) -> TriggerEffect {
        TriggerEffect(mode: 0x26, params: [0xFF &- start, keepEffect ? 0x02 : 0, 0, beginForce, middleForce,
                                           endForce, 0, 0, max(1, frequency / 2)])
    }

    /// Per-zone resistance. `strengths` holds 10 values (0-8) for the 10 travel zones; 0 = no resistance.
    public static func feedback(zones strengths: [UInt8]) -> TriggerEffect {
        var active: UInt16 = 0
        var packed: UInt32 = 0
        for (i, s) in strengths.prefix(10).enumerated() where s > 0 {
            active |= 1 << UInt16(i)
            packed |= UInt32((min(s, 8) - 1) & 0x07) << UInt32(3 * i)
        }
        if active == 0 { return .off }
        return TriggerEffect(mode: 0x21, params: zoneBytes(active, packed))
    }

    /// Per-zone vibration. `amplitudes` holds 10 values (0-8); `frequency` in Hz.
    public static func vibration(zones amplitudes: [UInt8], frequency: UInt8) -> TriggerEffect {
        var active: UInt16 = 0
        var packed: UInt32 = 0
        for (i, s) in amplitudes.prefix(10).enumerated() where s > 0 {
            active |= 1 << UInt16(i)
            packed |= UInt32((min(s, 8) - 1) & 0x07) << UInt32(3 * i)
        }
        if active == 0 || frequency == 0 { return .off }
        return TriggerEffect(mode: 0x26, params: zoneBytes(active, packed) + [0, 0, frequency])
    }

    /// Weapon-style click: resistance between zones `start` (2-7) and `end` (start+1...8), strength 1-8.
    public static func weapon(start: UInt8, end: UInt8, strength: UInt8) -> TriggerEffect {
        if strength == 0 { return .off }
        let zones: UInt16 = (1 << UInt16(start)) | (1 << UInt16(end))
        return TriggerEffect(mode: 0x25, params: [UInt8(zones & 0xff), UInt8(zones >> 8), min(strength, 8) - 1])
    }

    private static func zoneBytes(_ active: UInt16, _ packed: UInt32) -> [UInt8] {
        [UInt8(active & 0xff), UInt8(active >> 8),
         UInt8(packed & 0xff), UInt8((packed >> 8) & 0xff), UInt8((packed >> 16) & 0xff), UInt8((packed >> 24) & 0xff)]
    }
}

public enum MicLED: UInt8, Sendable, Codable { case off = 0, on = 1, pulse = 2 }

/// Everything the app can make the controller do, as one value.
public struct OutputState: Equatable, Sendable {
    public var rumbleLeft: UInt8 = 0    // heavy motor
    public var rumbleRight: UInt8 = 0   // light motor
    public var red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0
    public var playerLEDs: UInt8 = 0    // 5 bits, left to right
    public var playerBrightness: UInt8 = 0 // 0 high, 1 medium, 2 low
    public var micLED: MicLED = .off
    public var leftTrigger: TriggerEffect = .off
    public var rightTrigger: TriggerEffect = .off

    public init() {}
}

public enum OutputReport {
    public static let usbLength = 48
    public static let bluetoothLength = 78

    /// 47-byte payload shared by both transports.
    static func common(_ s: OutputState, releaseLEDs: Bool = false) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 47)
        b[0] = 0x01 | 0x02 | 0x04 | 0x08       // rumble, right trigger, left trigger
        b[1] = 0x01 | 0x04 | 0x10              // mic LED, lightbar, player LEDs
        if releaseLEDs { b[1] = 0x01 | 0x08 }  // mic LED off, hand the lightbar back to the firmware
        b[2] = s.rumbleRight
        b[3] = s.rumbleLeft
        b[8] = s.micLED.rawValue
        b[10] = s.rightTrigger.mode
        b.replaceSubrange(11..<21, with: s.rightTrigger.params)
        b[21] = s.leftTrigger.mode
        b.replaceSubrange(22..<32, with: s.leftTrigger.params)
        b[38] = 0x01                           // LED brightness control
        b[42] = s.playerBrightness
        b[43] = s.playerLEDs & 0x1f
        b[44] = s.red
        b[45] = s.green
        b[46] = s.blue
        return b
    }

    /// Full report including the report ID in byte 0.
    public static func encode(_ s: OutputState, transport: Transport, sequence: UInt8 = 0,
                              releaseLEDs: Bool = false) -> [UInt8] {
        switch transport {
        case .usb:
            return [0x02] + common(s, releaseLEDs: releaseLEDs)
        case .bluetooth:
            var b = [UInt8](repeating: 0, count: bluetoothLength)
            b[0] = 0x31
            b[1] = (sequence & 0x0f) << 4
            b[2] = 0x10
            b.replaceSubrange(3..<50, with: common(s, releaseLEDs: releaseLEDs))
            let crc = crc32(seed: [0xA2], b[0..<74])
            b[74] = UInt8(crc & 0xff)
            b[75] = UInt8((crc >> 8) & 0xff)
            b[76] = UInt8((crc >> 16) & 0xff)
            b[77] = UInt8((crc >> 24) & 0xff)
            return b
        }
    }

    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32<S: Sequence>(seed: [UInt8], _ data: S) -> UInt32 where S.Element == UInt8 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in seed { c = crcTable[Int((c ^ UInt32(byte)) & 0xff)] ^ (c >> 8) }
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xff)] ^ (c >> 8) }
        return ~c
    }
}

public enum ChargeState: Sendable, Equatable { case discharging, charging, full, unknown }

/// Decoded input report.
public struct InputState: Equatable, Sendable {
    public var leftX: UInt8 = 128, leftY: UInt8 = 128, rightX: UInt8 = 128, rightY: UInt8 = 128
    public var l2: UInt8 = 0, r2: UInt8 = 0
    public var buttons: UInt32 = 0
    public var batteryPercent: Int = 0
    public var charge: ChargeState = .unknown
    public var rightTriggerStatus: UInt8 = 0
    public var leftTriggerStatus: UInt8 = 0
    public var triggerEffectIDs: UInt8 = 0

    public var psButton: Bool { buttons & 0x010000 != 0 }

    public init() {}

    /// `report` includes the report ID in byte 0. Returns nil for reports that carry no full state.
    public static func parse(_ report: UnsafeBufferPointer<UInt8>) -> InputState? {
        guard let id = report.first else { return nil }
        let off: Int
        if id == 0x01, report.count >= 64 { off = 1 }
        else if id == 0x31, report.count >= 78 { off = 2 }
        else { return nil }
        var s = InputState()
        s.leftX = report[off]; s.leftY = report[off + 1]
        s.rightX = report[off + 2]; s.rightY = report[off + 3]
        s.l2 = report[off + 4]; s.r2 = report[off + 5]
        s.buttons = UInt32(report[off + 7]) | UInt32(report[off + 8]) << 8 | UInt32(report[off + 9]) << 16
        s.rightTriggerStatus = report[off + 41]
        s.leftTriggerStatus = report[off + 42]
        s.triggerEffectIDs = report[off + 47]
        let status = report[off + 52]
        let level = Int(status & 0x0f)
        s.batteryPercent = min(100, level * 10 + 5)
        switch status >> 4 {
        case 0: s.charge = .discharging
        case 1: s.charge = .charging
        case 2: s.charge = .full; s.batteryPercent = 100
        default: s.charge = .unknown
        }
        return s
    }
}
