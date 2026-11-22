// Hardware proof of concept: detect a DualSense, then exercise triggers, rumble and LEDs.
import DualSenseKit
import EffectKit
import Foundation

if CommandLine.arguments.contains("telemetry") {
    let reader = TelemetryReader()
    for _ in 0..<(CommandLine.arguments.contains("watch") ? 600 : 3) {
        if let s = reader.read() {
            let t = s.truck
            print(String(format: "sdk=%d age=%.0fms seq=%u paused=%d game=%d engine=%d  %.1f km/h  rpm %.0f/%.0f  gear %@  thr %.2f brk %.2f  fuel %.0f%%  park=%d wheels=%d  truck='%@ %@' sub=%@",
                         s.sdkActive ? 1 : 0, s.ageMs, s.frameSeq, t.paused ? 1 : 0, t.game, t.engineEnabled ? 1 : 0, t.speedKmh,
                         t.engineRpm, t.engineRpmMax, t.gearLabel as NSString, t.inputThrottle, t.inputBrake, t.fuelPercent,
                         t.parkBrake ? 1 : 0, t.wheelCount, t.truckBrand as NSString, t.truckName as NSString,
                         t.wheelSubstance.joined(separator: ",") as NSString))
        } else { print("no telemetry file") }
        Thread.sleep(forTimeInterval: 0.5)
    }
    exit(0)
}
let mgr = DualSenseManager()
mgr.onLog = { print("[hid] \($0)") }
mgr.start()

func wait(_ s: Double) { Thread.sleep(forTimeInterval: s) }
func hex(_ v: UInt8) -> String { String(format: "%02x", v) }

var tries = 0
while mgr.device == nil && tries < 50 { wait(0.1); tries += 1 }
guard let dev = mgr.device else { print("No DualSense found"); exit(1) }
print("Device: \(dev.name)  transport=\(dev.transport.rawValue)  serial=\(dev.serial)  pid=0x\(String(dev.productID, radix: 16))")
wait(0.5)

func snapshot(_ label: String) {
    let i = mgr.input, s = mgr.stats
    print(String(format: "%-28@ ok=%@ send=%.0fus  in#=%llu L2=%3d R2=%3d  Lstat=%@ Rstat=%@ fx=%@  batt=%d%% %@",
                 label as NSString, (s.lastResult == 0 ? "yes" : DualSenseManager.describe(s.lastResult)) as NSString,
                 s.lastSendMicros, s.inputReports, i.l2, i.r2,
                 hex(i.leftTriggerStatus) as NSString, hex(i.rightTriggerStatus) as NSString, hex(i.triggerEffectIDs) as NSString,
                 i.batteryPercent, "\(i.charge)" as NSString))
}

if CommandLine.arguments.contains("read") {
    for _ in 0..<2 {
        let i = mgr.input
        print("LX=\(i.leftX) LY=\(i.leftY) RX=\(i.rightX) RY=\(i.rightY) L2=\(i.l2) R2=\(i.r2) buttons=\(String(i.buttons, radix: 16)) Lstat=\(hex(i.leftTriggerStatus)) Rstat=\(hex(i.rightTriggerStatus)) fx=\(hex(i.triggerEffectIDs)) reports=\(mgr.stats.inputReports)")
        wait(0.3)
    }
    exit(0)
}
let hold = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 1.5
var o = OutputState()
snapshot("baseline")

o.leftTrigger = .continuous(start: 0, force: 200)
o.red = 255
mgr.send(o); wait(hold); snapshot("L2 continuous, red")

o.leftTrigger = .off
o.rightTrigger = .feedback(zones: [0, 0, 2, 3, 4, 5, 6, 7, 8, 8])
o.red = 0; o.green = 255
mgr.send(o); wait(hold); snapshot("R2 feedback ramp, green")

o.rightTrigger = .vibration(zones: [UInt8](repeating: 6, count: 10), frequency: 30)
o.green = 0; o.blue = 255
mgr.send(o); wait(hold); snapshot("R2 vibration 30Hz, blue")

o.rightTrigger = .off
o.rumbleLeft = 160
mgr.send(o); wait(hold / 2); snapshot("rumble heavy")
o.rumbleLeft = 0; o.rumbleRight = 160
mgr.send(o); wait(hold / 2); snapshot("rumble light")

o.rumbleRight = 0
o.blue = 0; o.red = 255; o.green = 255
o.playerLEDs = 0x1f; o.micLED = .pulse
mgr.send(o); wait(hold); snapshot("player LEDs, mic pulse")

mgr.reset(); wait(0.3); snapshot("reset")
print("max send \(Int(mgr.stats.maxSendMicros))us, failures \(mgr.stats.sendFailures)")
