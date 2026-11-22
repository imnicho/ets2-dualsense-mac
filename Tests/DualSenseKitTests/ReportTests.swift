import XCTest
@testable import DualSenseKit

final class ReportTests: XCTestCase {
    func testCRC32KnownVector() {
        XCTAssertEqual(OutputReport.crc32(seed: [], Array("123456789".utf8)), 0xCBF43926)
    }

    func testUSBReportLayout() {
        var s = OutputState()
        s.rumbleLeft = 10; s.rumbleRight = 20
        s.red = 1; s.green = 2; s.blue = 3
        s.playerLEDs = 0xff; s.playerBrightness = 2; s.micLED = .pulse
        s.leftTrigger = .continuous(start: 0, force: 200)
        s.rightTrigger = .effectEx(start: 0, keepEffect: true, beginForce: 0, middleForce: 0, endForce: 0, frequency: 100)
        let r = OutputReport.encode(s, transport: .usb)
        XCTAssertEqual(r.count, 48)
        XCTAssertEqual(r[0], 0x02)
        XCTAssertEqual(r[1] & 0x0f, 0x0f)
        XCTAssertEqual(r[3], 20); XCTAssertEqual(r[4], 10)
        XCTAssertEqual(r[9], 2)
        // Right trigger block, as emitted by the Windows mod: 26 FF 02 00 00 00 00 00 00 freq/2
        XCTAssertEqual(Array(r[11...20]), [0x26, 0xFF, 0x02, 0, 0, 0, 0, 0, 0, 50])
        // Left trigger block: 01 00 force
        XCTAssertEqual(Array(r[22...24]), [0x01, 0x00, 200])
        XCTAssertEqual(r[43], 2)
        XCTAssertEqual(r[44], 0x1f)
        XCTAssertEqual(Array(r[45...47]), [1, 2, 3])
    }

    func testBluetoothReportFramingAndCRC() {
        var s = OutputState()
        s.red = 255
        let r = OutputReport.encode(s, transport: .bluetooth, sequence: 5)
        XCTAssertEqual(r.count, 78)
        XCTAssertEqual(r[0], 0x31)
        XCTAssertEqual(r[1], 0x50)
        XCTAssertEqual(r[2], 0x10)
        XCTAssertEqual(Array(r[3..<50]), Array(OutputReport.encode(s, transport: .usb)[1...]))
        let crc = OutputReport.crc32(seed: [0xA2], r[0..<74])
        XCTAssertEqual(r[74], UInt8(crc & 0xff))
        XCTAssertEqual(r[77], UInt8(crc >> 24))
    }

    func testThrottleFrequencyIdlesAtOne() {
        let e = TriggerEffect.effectEx(start: 0, keepEffect: true, beginForce: 0, middleForce: 0, endForce: 0, frequency: 0)
        XCTAssertEqual(e.params[8], 1)
    }

    func testZeroForceIsOff() {
        XCTAssertEqual(TriggerEffect.continuous(start: 0, force: 0), .off)
        XCTAssertEqual(TriggerEffect.feedback(zones: [UInt8](repeating: 0, count: 10)), .off)
        XCTAssertEqual(TriggerEffect.off.mode, 0x05)
    }

    func testFeedbackZonePacking() {
        // zones 2 and 9 active with strengths 1 and 8
        let e = TriggerEffect.feedback(zones: [0, 0, 1, 0, 0, 0, 0, 0, 0, 8])
        XCTAssertEqual(e.mode, 0x21)
        XCTAssertEqual(e.params[0], 0x04)
        XCTAssertEqual(e.params[1], 0x02)
        let packed = UInt32(e.params[2]) | UInt32(e.params[3]) << 8 | UInt32(e.params[4]) << 16 | UInt32(e.params[5]) << 24
        XCTAssertEqual(packed, UInt32(7) << 27)
    }

    func testVibrationFrequencyByte() {
        let e = TriggerEffect.vibration(zones: [UInt8](repeating: 8, count: 10), frequency: 30)
        XCTAssertEqual(e.mode, 0x26)
        XCTAssertEqual(e.params[0], 0xff); XCTAssertEqual(e.params[1], 0x03)
        XCTAssertEqual(e.params[8], 30)
    }

    func testResetReleasesLEDs() {
        let r = OutputReport.encode(OutputState(), transport: .usb, releaseLEDs: true)
        XCTAssertEqual(r[2] & 0x08, 0x08)
        XCTAssertEqual(r[2] & 0x04, 0)
        XCTAssertEqual(r[11], 0x05); XCTAssertEqual(r[22], 0x05)
    }

    private func parse(_ bytes: [UInt8]) -> InputState? {
        bytes.withUnsafeBufferPointer { InputState.parse($0) }
    }

    func testInputParsingUSBAndBluetooth() {
        var usb = [UInt8](repeating: 0, count: 64)
        usb[0] = 0x01; usb[1] = 10; usb[5] = 77; usb[6] = 99; usb[10] = 0x01; usb[53] = 0x18
        let u = parse(usb)!
        XCTAssertEqual(u.leftX, 10); XCTAssertEqual(u.l2, 77); XCTAssertEqual(u.r2, 99)
        XCTAssertTrue(u.psButton)
        XCTAssertEqual(u.batteryPercent, 85); XCTAssertEqual(u.charge, .charging)

        var bt = [UInt8](repeating: 0, count: 78)
        bt[0] = 0x31; bt[6] = 77; bt[54] = 0x25
        let b = parse(bt)!
        XCTAssertEqual(b.l2, 77); XCTAssertEqual(b.charge, .full); XCTAssertEqual(b.batteryPercent, 100)
    }

    func testShortBluetoothReportIsIgnored() {
        var simple = [UInt8](repeating: 0, count: 10)
        simple[0] = 0x01
        XCTAssertNil(parse(simple))
        XCTAssertNil(parse([]))
    }
}
