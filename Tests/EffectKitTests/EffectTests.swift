import XCTest
import CTelemetry
import DualSenseKit
@testable import EffectKit

final class EffectTests: XCTestCase {
    func driving(_ edit: (inout TruckState) -> Void = { _ in }) -> TruckState {
        var t = TruckState()
        t.paused = false; t.engineEnabled = true
        t.engineRpmMax = 2500; t.engineRpm = 1300
        t.fuelCapacity = 1000; t.fuel = 950
        t.gear = 6
        edit(&t)
        return t
    }

    // MARK: curves

    func testCurveInterpolationAndClamping() {
        XCTAssertEqual(Curve.linear.value(at: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Curve.linear.value(at: 0.6), 0.6, accuracy: 1e-9)
        XCTAssertEqual(Curve.linear.value(at: -3), 0)
        XCTAssertEqual(Curve.linear.value(at: 7), 1)
        XCTAssertEqual(Curve.linear.value(at: .nan), 0)
        XCTAssertEqual(Curve([0, 1, 0, 1, 0]).value(at: 0.125), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Curve.flat.value(at: 0), 1)
        for (_, c) in Curve.presets { for x in stride(from: 0.0, through: 1, by: 0.05) { XCTAssert((0...1).contains(c.value(at: x))) } }
    }

    // MARK: original behaviour

    func testOriginalBrakeTriggerScalesWithSpeed() {
        var e = EffectEngine()
        var o = e.step(driving { $0.speed = 45 / 3.6 }, profile: .original, now: 0).output
        XCTAssertEqual(o.leftTrigger, .continuous(start: 0, force: 100))
        o = e.step(driving { $0.speed = 200 / 3.6 }, profile: .original, now: 0.016).output
        XCTAssertEqual(o.leftTrigger, .continuous(start: 0, force: 200))
        o = e.step(driving { $0.speed = 0 }, profile: .original, now: 0.033).output
        XCTAssertEqual(o.leftTrigger, .off)
    }

    func testOriginalThrottleFrequencyBands() {
        var e = EffectEngine()
        func freq(_ rpm: Float) -> UInt8 {
            e.step(driving { $0.engineRpm = rpm }, profile: .original, now: 0).output.rightTrigger.params[8]
        }
        // low = 940, high = 1915 for a 2500 rpm limit
        XCTAssertEqual(freq(550), 100)   // 200 / 2
        XCTAssertEqual(freq(1300), 1)    // calm band idles at 1
        XCTAssertEqual(freq(2500), 127)  // 255 / 2
        XCTAssertEqual(freq(745), 50)
    }

    func testTriggersOffWhenEngineOffOrPaused() {
        var e = EffectEngine()
        var r = e.step(driving { $0.engineEnabled = false; $0.speed = 20 }, profile: .original, now: 0)
        XCTAssertEqual(r.output.leftTrigger, .off); XCTAssertEqual(r.output.rightTrigger, .off)
        r = e.step(driving { $0.paused = true; $0.speed = 20; $0.parkBrake = true }, profile: .immersive, now: 1)
        XCTAssertEqual(r.output, OutputState())
        XCTAssertTrue(r.active.isEmpty)
    }

    func testGearJoltIsTwoFrames() {
        var e = EffectEngine()
        _ = e.step(driving { $0.gear = 3 }, profile: .original, now: 0)
        let a = e.step(driving { $0.gear = 4 }, profile: .original, now: 0.016)
        XCTAssertEqual(a.output.rumbleLeft, 255); XCTAssertEqual(a.output.rumbleRight, 100)
        XCTAssertTrue(a.active.contains(.gearJolt))
        let b = e.step(driving { $0.gear = 4 }, profile: .original, now: 0.033)
        XCTAssertEqual(b.output.rumbleLeft, 100); XCTAssertEqual(b.output.rumbleRight, 255)
        let c = e.step(driving { $0.gear = 4 }, profile: .original, now: 0.05)
        XCTAssertEqual(c.output.rumbleLeft, 0)
        // into or out of neutral: no jolt
        let d = e.step(driving { $0.gear = 0 }, profile: .original, now: 0.066)
        XCTAssertFalse(d.active.contains(.gearJolt))
    }

    func testNoSpuriousEventsWhenConnectingMidDrive() {
        var e = EffectEngine()
        let r = e.step(driving { $0.gear = 8; $0.fined = true; $0.speed = 20 }, profile: .original, now: 100)
        XCTAssertFalse(r.active.contains(.gearJolt))
        XCTAssertFalse(r.active.contains(.startLurch))
        XCTAssertFalse(r.active.contains(.fineAlert))
    }

    func testEngineStartLurchLasts1500ms() {
        var e = EffectEngine()
        _ = e.step(driving { $0.engineEnabled = false; $0.engineRpm = 0 }, profile: .original, now: 0)
        let crank = e.step(driving { $0.engineEnabled = false; $0.engineRpm = 300 }, profile: .original, now: 0.016)
        XCTAssertTrue(crank.active.contains(.cranking))
        _ = e.step(driving(), profile: .original, now: 1)
        let mid = e.step(driving(), profile: .original, now: 1.75)
        XCTAssertTrue(mid.active.contains(.startLurch))
        XCTAssertEqual(mid.output.rumbleLeft, 255)
        let after = e.step(driving(), profile: .original, now: 2.6)
        XCTAssertFalse(after.active.contains(.startLurch))
    }

    func testFineAlertFlashesFiveSeconds() {
        var e = EffectEngine()
        _ = e.step(driving(), profile: .original, now: 0)
        let a = e.step(driving { $0.fined = true }, profile: .original, now: 1)
        XCTAssertTrue(a.active.contains(.fineAlert))
        XCTAssertEqual(a.output.red, 255)
        let blue = e.step(driving { $0.fined = true }, profile: .original, now: 2.1)
        XCTAssertEqual(blue.output.blue, 255)
        let done = e.step(driving { $0.fined = true }, profile: .original, now: 6.5)
        XCTAssertFalse(done.active.contains(.fineAlert))
    }

    func testLightbarPriority() {
        var e = EffectEngine()
        var o = e.step(driving { $0.parkBrake = true; $0.blinkerLeftOn = true }, profile: .original, now: 0).output
        XCTAssertEqual([o.red, o.green, o.blue], [255, 0, 0])
        o = e.step(driving { $0.blinkerLeftOn = true }, profile: .original, now: 0).output
        XCTAssertEqual([o.red, o.green, o.blue], [0, 255, 0])
        o = e.step(driving { $0.blinkerLeftOn = true; $0.blinkerRightOn = true }, profile: .original, now: 0).output
        XCTAssertEqual([o.red, o.green, o.blue], [255, 255, 0])
        var dim = Profile.original
        dim.lighting.brightness = 0.5
        o = e.step(driving { $0.parkBrake = true }, profile: dim, now: 0).output
        XCTAssertEqual(o.red, 127)
    }

    func testFuelGaugeAndMicLED() {
        var e = EffectEngine()
        var o = e.step(driving { $0.fuel = 950 }, profile: .original, now: 0).output
        XCTAssertEqual(o.playerLEDs, 0x1f)
        o = e.step(driving { $0.fuel = 450 }, profile: .original, now: 0).output
        XCTAssertEqual(o.playerLEDs, 0x15)
        o = e.step(driving { $0.fuel = 50 }, profile: .original, now: 0).output
        XCTAssertEqual(o.playerLEDs, 0x04)
        o = e.step(driving { $0.oilPressureWarning = true }, profile: .original, now: 0).output
        XCTAssertEqual(o.micLED, .pulse)
        o = e.step(driving { $0.adblueWarning = true }, profile: .original, now: 0).output
        XCTAssertEqual(o.micLED, .on)
    }

    func testHardBrakingBeatsBodyRoll() {
        var e = EffectEngine()
        _ = e.step(driving { $0.speed = 20 }, profile: .original, now: 0)
        let r = e.step(driving { $0.speed = 19.8; $0.inputBrake = 1; $0.roll = 0.01 }, profile: .original, now: 0.016)
        XCTAssertTrue(r.active.contains(.hardBraking))
        XCTAssertFalse(r.active.contains(.bodyRoll))
    }

    // MARK: additions

    func testCustomBrakeUsesCurveMinMaxAndDeadZone() {
        var p = Profile(name: "t")
        p.brake.style = .custom; p.brake.source = .pedal; p.brake.smoothing = 0
        p.brake.minForce = 0.2; p.brake.maxForce = 0.6; p.brake.deadZone = 0.1
        var e = EffectEngine()
        var o = e.step(driving { $0.effectiveBrake = 0 }, profile: p, now: 0).output
        XCTAssertEqual(o.leftTrigger, .continuous(start: 25, force: 51))
        o = e.step(driving { $0.effectiveBrake = 1 }, profile: p, now: 0).output
        XCTAssertEqual(o.leftTrigger, .continuous(start: 25, force: 153))
        p.brake.intensity = 0.5
        o = e.step(driving { $0.effectiveBrake = 1 }, profile: p, now: 0).output
        XCTAssertEqual(o.leftTrigger.params[1], 77)
        p.brake.enabled = false
        XCTAssertEqual(e.step(driving(), profile: p, now: 0).output.leftTrigger, .off)
    }

    func testSmoothingConvergesGradually() {
        var p = Profile(name: "t")
        p.brake.style = .custom; p.brake.source = .pedal; p.brake.smoothing = 0.8; p.brake.maxForce = 1
        var e = EffectEngine()
        let first = e.step(driving { $0.effectiveBrake = 1 }, profile: p, now: 0).output.leftTrigger.params[1]
        XCTAssertLessThan(first, 100)
        var last: UInt8 = 0
        for _ in 0..<200 { last = e.step(driving { $0.effectiveBrake = 1 }, profile: p, now: 0).output.leftTrigger.params[1] }
        XCTAssertGreaterThan(last, 250)
    }

    func testSimulatedABSPulseOnWheelSlip() {
        var p = Profile.realistic
        p.brake.pulse = true
        var e = EffectEngine()
        let slip = driving {
            $0.speed = 20; $0.inputBrake = 0.9; $0.wheelCount = 2
            $0.wheelRadius = [0.5, 0.5]; $0.wheelOnGround = [true, true]; $0.wheelAngularVelocity = [0, 6.3]
        }
        _ = e.step(slip, profile: p, now: 0)
        let r = e.step(slip, profile: p, now: 0.016)
        XCTAssertTrue(r.active.contains(.absPulse))
        XCTAssertEqual(r.output.leftTrigger.mode, 0x26)
        let grip = driving {
            $0.speed = 20; $0.inputBrake = 0.9; $0.wheelCount = 2
            $0.wheelRadius = [0.5, 0.5]; $0.wheelOnGround = [true, true]; $0.wheelAngularVelocity = [6.3, 6.3]
        }
        XCTAssertFalse(e.step(grip, profile: p, now: 0.033).active.contains(.absPulse))
    }

    func testThrottleReleasesDuringGearChange() {
        var p = Profile(name: "t")
        p.throttle.style = .custom; p.throttle.source = .rpm; p.throttle.smoothing = 0; p.throttle.maxForce = 1
        p.throttle.shiftRelease = true; p.throttle.shiftReleaseTime = 0.3
        var e = EffectEngine()
        XCTAssertNotEqual(e.step(driving { $0.gear = 3 }, profile: p, now: 0).output.rightTrigger, .off)
        let shift = e.step(driving { $0.gear = 4 }, profile: p, now: 0.016)
        XCTAssertEqual(shift.output.rightTrigger, .off)
        XCTAssertTrue(shift.active.contains(.shiftRelease))
        XCTAssertEqual(e.step(driving { $0.gear = 4 }, profile: p, now: 0.2).output.rightTrigger, .off)
        XCTAssertNotEqual(e.step(driving { $0.gear = 4 }, profile: p, now: 0.4).output.rightTrigger, .off)
        // engaging from neutral is not a shift
        _ = e.step(driving { $0.gear = 0 }, profile: p, now: 1)
        XCTAssertNotEqual(e.step(driving { $0.gear = 1 }, profile: p, now: 1.016).output.rightTrigger, .off)
        // off by default, and in the Classic profile
        p.throttle.shiftRelease = false
        XCTAssertNotEqual(e.step(driving { $0.gear = 2 }, profile: p, now: 2).output.rightTrigger, .off)
        XCTAssertFalse(Profile.original.throttle.shiftRelease)
    }

    func testOlderSavedProfilesStillLoad() throws {
        // A trigger block written before newer settings existed.
        var object = try JSONSerialization.jsonObject(with: ProfileStore.export(.realistic)) as! [String: Any]
        var throttle = object["throttle"] as! [String: Any]
        throttle.removeValue(forKey: "shiftRelease"); throttle.removeValue(forKey: "shiftReleaseTime")
        object["throttle"] = throttle
        let p = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(p.throttle.shiftRelease)
        XCTAssertEqual(p.throttle.maxForce, Profile.realistic.throttle.maxForce)
    }

    /// Peak rumble a Preview button produces for the given slider position.
    func previewPeak(_ preview: EffectPreview, _ path: WritableKeyPath<HapticsConfig, HapticEffect>, intensity: Double) -> UInt8 {
        var p = Profile.original
        p.haptics[keyPath: path] = HapticEffect(true, intensity)
        let profile = preview.enabling(in: p)
        var e = EffectEngine()
        var peak: UInt8 = 0
        var t = 0.0
        while t < preview.duration {
            let o = e.step(preview.truck(at: t), profile: profile, now: 100 + t).output
            peak = max(peak, o.rumbleLeft, o.rumbleRight)
            t += EffectEngine.frameInterval
        }
        return peak
    }

    func testPreviewFollowsIntensitySlider() {
        let cases: [(EffectPreview, WritableKeyPath<HapticsConfig, HapticEffect>)] = [
            (.hardBraking, \.hardBraking), (.gearJolt, \.gearJolt), (.engineStart, \.engineStart), (.bodyRoll, \.bodyRoll),
            (.refuel, \.refuel), (.fineAlert, \.fineAlert), (.collision, \.collision), (.roadSurface, \.roadSurface),
        ]
        for (preview, path) in cases {
            let full = previewPeak(preview, path, intensity: 1)
            let half = previewPeak(preview, path, intensity: 0.5)
            let zero = previewPeak(preview, path, intensity: 0)
            print("PREVIEW \(preview.rawValue): 100% -> \(full), 50% -> \(half), 0% -> \(zero)")
            XCTAssertGreaterThan(full, 100, preview.rawValue)
            XCTAssertLessThan(Int(half), Int(full) * 6 / 10, preview.rawValue)
            XCTAssertEqual(zero, 0, preview.rawValue)
        }
    }

    func testCollisionFromDamageIncrease() {
        var e = EffectEngine()
        _ = e.step(driving(), profile: .immersive, now: 0)
        let r = e.step(driving { $0.wearChassis = 0.05 }, profile: .immersive, now: 0.016)
        XCTAssertTrue(r.active.contains(.collision))
        XCTAssertGreaterThan(r.output.rumbleLeft, 150)
        XCTAssertFalse(e.step(driving { $0.wearChassis = 0.05 }, profile: .immersive, now: 1).active.contains(.collision))
    }

    func testMixingAndLimit() {
        var p = Profile.original
        p.haptics.engineIdle = HapticEffect(true, 1)
        p.haptics.limit = 0.5
        var e = EffectEngine()
        _ = e.step(driving { $0.gear = 3 }, profile: p, now: 0)
        let capped = e.step(driving { $0.gear = 4 }, profile: p, now: 0.016).output
        XCTAssertEqual(capped.rumbleLeft, 127)
        p.haptics.limit = 1; p.haptics.mix = .additive
        var e2 = EffectEngine()
        _ = e2.step(driving { $0.gear = 3 }, profile: p, now: 0)
        let added = e2.step(driving { $0.gear = 4 }, profile: p, now: 0.016).output
        XCTAssertGreaterThan(added.rumbleRight, 100) // jolt 100 + engine vibration
        p.haptics.master = 0
        XCTAssertEqual(e2.step(driving { $0.gear = 5 }, profile: p, now: 0.033).output.rumbleLeft, 0)
    }

    func testMissingTelemetryValuesAreSafe() {
        var e = EffectEngine()
        var t = TruckState()
        t.paused = false; t.engineEnabled = true
        t.speed = .nan; t.engineRpm = .infinity; t.roll = .nan
        for p in Profile.builtIns { _ = e.step(t, profile: p, now: 0) }
        t = TruckState(); t.paused = false; t.engineEnabled = true // rpm limit 0, capacity 0
        for p in Profile.builtIns { _ = e.step(t, profile: p, now: 0) }
    }

    // MARK: recorded drive regression

    func testSimulatedDriveProducesExpectedEffects() {
        for profile in Profile.builtIns {
            var sim = TelemetrySimulator()
            var e = EffectEngine()
            var seen: ActiveEffects = []
            var now = 0.0
            for _ in 0..<Int(TelemetrySimulator.cycle * 60) {
                let r = e.step(sim.step(), profile: profile, now: now)
                seen.formUnion(r.active)
                XCTAssertLessThanOrEqual(Double(r.output.rumbleLeft), profile.haptics.limit * 255 + 1)
                now += EffectEngine.frameInterval
            }
            for expected: ActiveEffects in [.cranking, .startLurch, .gearJolt, .hardBraking, .refuel, .fineAlert, .brakeTrigger, .throttleTrigger] {
                XCTAssertTrue(seen.contains(expected), "\(profile.name) never produced \(expected.labels)")
            }
            if profile.haptics.bodyRoll.enabled { XCTAssertTrue(seen.contains(.bodyRoll), profile.name) }
            if profile.haptics.roadSurface.enabled { XCTAssertTrue(seen.contains(.roadSurface), profile.name) }
        }
    }

    // MARK: rim steering

    func testRimSteeringFollowsStickRotation() {
        var rim = RimSteering()
        let c = RimConfig()
        XCTAssertEqual(rim.step(x: 0, y: 0, speedMs: 0, config: c), 0)
        _ = rim.step(x: 0, y: 127, speedMs: 0, config: c)           // grab at 12 o'clock
        let quarter = rim.step(x: 127, y: 0, speedMs: 0, config: c) // rotate to 3 o'clock
        XCTAssertEqual(quarter, 90.0 / 450.0, accuracy: 1e-6)
        let fast = rim.step(x: 0, y: -127, speedMs: 25, config: c)  // same again at 90 km/h: 5x less
        XCTAssertEqual(fast - quarter, 90.0 / 450.0 / 5, accuracy: 1e-6)
        _ = rim.step(x: 0, y: 0, speedMs: 0, config: c)             // letting go keeps the angle
        XCTAssertEqual(rim.steer, (90 + 18) * .pi / 180, accuracy: 1e-6)
    }

    // MARK: profiles

    func testProfileRoundTripAndImport() throws {
        var p = Profile.immersive
        p.truckMatch = "scania"
        let data = try ProfileStore.export(p)
        let back = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(back, p)
        let imported = try ProfileStore.importProfile(data)
        XCTAssertNotEqual(imported.id, p.id)
        XCTAssertFalse(imported.builtIn)
        XCTAssertThrowsError(try ProfileStore.importProfile(Data("not json".utf8)))
    }

    func testProfileStorePersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ets2ds-\(UUID().uuidString)/profiles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ProfileStore(url: url)
        XCTAssertEqual(store.load().selected, Profile.original.id)
        var custom = Profile(name: "Mine")
        custom.brake.maxForce = 0.33
        try store.save(.init(selected: custom.id, custom: [custom]))
        XCTAssertEqual(store.load(), .init(selected: custom.id, custom: [custom]))
        try Data("garbage".utf8).write(to: url)
        XCTAssertEqual(store.load().custom, [])
    }

    func testTruckMatch() {
        var p = Profile(name: "x")
        var t = TruckState(); t.truckBrand = "Scania"; t.truckName = "S 2016"
        XCTAssertFalse(p.matches(t))
        p.truckMatch = "scania s"
        XCTAssertTrue(p.matches(t))
        p.truckMatch = "volvo"
        XCTAssertFalse(p.matches(t))
    }

    func testBuiltInIDsAreUniqueAndOriginalMatchesWindowsDefaults() {
        XCTAssertEqual(Set(Profile.builtIns.map(\.id)).count, Profile.builtIns.count)
        let o = Profile.original
        XCTAssertEqual(o.brake.style, .original); XCTAssertEqual(o.throttle.style, .original)
        XCTAssertFalse(o.rim.enabled); XCTAssertEqual(o.rim.lockDegrees, 450)
        XCTAssertFalse(o.haptics.engineIdle.enabled); XCTAssertEqual(o.haptics.mix, .strongest)
    }

    // MARK: telemetry file

    func testTelemetryReaderParsesMappedFile() throws {
        let path = NSTemporaryDirectory() + "ets2ds-test-\(UUID().uuidString)"
        defer { unlink(path) }
        let missing = TelemetryReader(path: path)
        XCTAssertNil(missing.read())

        var raw = Telemetry()
        raw.magic = ETS2DS_MAGIC
        raw.seq = 4
        raw.heartbeatMs = TelemetryReader.nowMs()
        raw.sdkActive = 1
        raw.engineEnabled = 1
        raw.gear = -1
        raw.speed = 10
        raw.engineRpm = 1200; raw.engineRpmMax = 2400
        raw.fuel = 250; raw.fuelCapacity = 500
        raw.wheelCount = 2
        raw.wheelRadius.0 = 0.5; raw.wheelRadius.1 = 0.6
        raw.wheelOnGround.1 = 1
        raw.wheelSubstance.1 = 3
        withUnsafeMutableBytes(of: &raw.substances) { $0.baseAddress!.advanced(by: 3 * 32).copyMemory(from: "gravel", byteCount: 6) }
        withUnsafeMutableBytes(of: &raw.truckBrand) { $0.baseAddress!.copyMemory(from: "Volvo", byteCount: 5) }
        try withUnsafeBytes(of: raw) { Data($0) }.write(to: URL(fileURLWithPath: path))

        let reader = TelemetryReader(path: path)
        let s = try XCTUnwrap(reader.read())
        XCTAssertTrue(s.sdkActive)
        XCTAssertLessThan(s.ageMs, 1000)
        XCTAssertEqual(s.truck.gearLabel, "R1")
        XCTAssertEqual(s.truck.speedKmh, 36, accuracy: 0.01)
        XCTAssertEqual(s.truck.rpmFraction, 0.5)
        XCTAssertEqual(s.truck.fuelPercent, 50)
        XCTAssertEqual(s.truck.wheelRadius, [0.5, 0.6])
        XCTAssertEqual(s.truck.wheelOnGround, [false, true])
        XCTAssertEqual(s.truck.wheelSubstance, ["", "gravel"])
        XCTAssertEqual(s.truck.truckBrand, "Volvo")
    }

    func testTelemetryReaderRejectsForeignAndShortFiles() throws {
        let path = NSTemporaryDirectory() + "ets2ds-test-\(UUID().uuidString)"
        defer { unlink(path) }
        try Data(repeating: 0, count: 16).write(to: URL(fileURLWithPath: path))
        XCTAssertNil(TelemetryReader(path: path).read())
        try Data(repeating: 0x55, count: MemoryLayout<Telemetry>.size).write(to: URL(fileURLWithPath: path))
        XCTAssertNil(TelemetryReader(path: path).read())
    }
}
