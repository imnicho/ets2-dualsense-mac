import DualSenseKit
import EffectKit
import SwiftUI

// MARK: - Adaptive triggers

struct TriggerStudioView: View {
    @Environment(AppModel.self) private var model
    @State private var testing = false
    @State private var testSpeed = 60.0
    @State private var testRpm = 0.5
    @State private var testPedal = 0.5

    var body: some View {
        @Bindable var model = model
        PageScroll {
            HStack(alignment: .top, spacing: 16) {
                TriggerEditor(title: "L2 · Brake", isBrake: true, config: $model.profile.brake,
                              position: Double(model.snap.input.l2) / 255, effect: model.snap.output.leftTrigger,
                              drive: drive(model.profile.brake, pedal: Double(driveTruck.effectiveBrake)))
                TriggerEditor(title: "R2 · Accelerator", isBrake: false, config: $model.profile.throttle,
                              position: Double(model.snap.input.r2) / 255, effect: model.snap.output.rightTrigger,
                              drive: drive(model.profile.throttle, pedal: Double(driveTruck.effectiveThrottle)))
            }
            Card(title: "Test Bench", icon: "testtube.2") {
                Toggle("Drive the triggers from these sliders instead of the game", isOn: $testing)
                Group {
                    SliderRow(title: "Speed", value: $testSpeed, range: 0...130) { "\(Int($0)) km/h" }
                    SliderRow(title: "Engine RPM", value: $testRpm)
                    SliderRow(title: "Pedal pressure", value: $testPedal)
                }
                .disabled(!testing)
                Text("Squeeze L2 and R2 while moving the sliders to feel each setting. Changes apply immediately.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: testing) { push() }
        .onChange(of: testSpeed) { push() }
        .onChange(of: testRpm) { push() }
        .onChange(of: testPedal) { push() }
        .onDisappear { testing = false; model.runtime.set(manual: nil) }
    }

    private var testTruck: TruckState {
        var t = TruckState()
        t.paused = false; t.engineEnabled = true
        t.speed = Float(testSpeed / 3.6)
        t.engineRpmMax = 2500; t.engineRpm = Float(testRpm * 2500)
        t.effectiveBrake = Float(testPedal); t.effectiveThrottle = Float(testPedal)
        t.fuelCapacity = 1; t.fuel = 1
        return t
    }

    private var driveTruck: TruckState { testing ? testTruck : model.snap.truck }

    private func drive(_ c: TriggerConfig, pedal: Double) -> Double {
        let t = driveTruck
        switch c.source {
        case .speed: return Double(min(1, abs(t.speedKmh) / 90))
        case .rpm: return Double(t.rpmFraction)
        case .pedal: return pedal
        case .deceleration: return 0
        }
    }

    private func push() { model.runtime.set(manual: testing ? testTruck : nil) }
}

struct TriggerEditor: View {
    let title: String
    let isBrake: Bool
    @Binding var config: TriggerConfig
    let position: Double
    let effect: TriggerEffect
    let drive: Double

    var body: some View {
        Card(title: title, icon: isBrake ? "l2.button.roundedtop.horizontal" : "r2.button.roundedtop.horizontal") {
            Toggle("Enabled", isOn: $config.enabled)
            Group {
                Picker("Behaviour", selection: $config.style) {
                    Text("Classic").tag(TriggerStyle.original)
                    Text("Custom curve").tag(TriggerStyle.custom)
                }
                .pickerStyle(.segmented)
                Text(styleNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SliderRow(title: "Intensity", value: $config.intensity)

                if config.style == .custom {
                    Picker("Driven by", selection: $config.source) {
                        ForEach(sources, id: \.self) { Text($0.label).tag($0) }
                    }
                    HStack {
                        Text("Resistance curve").font(.subheadline.weight(.medium))
                        Spacer()
                        Menu("Preset") {
                            ForEach(Curve.presets, id: \.0) { name, curve in Button(name) { config.curve = curve } }
                        }
                        .fixedSize()
                    }
                    CurveEditor(curve: $config.curve, marker: drive)
                    SliderRow(title: "Minimum resistance", value: $config.minForce)
                    SliderRow(title: "Maximum resistance", value: $config.maxForce)
                    SliderRow(title: "Dead zone", value: $config.deadZone, range: 0...0.8)
                    SliderRow(title: "Smoothing", value: $config.smoothing)
                    Divider()
                    Toggle(isOn: $config.pulse) {
                        HStack {
                            Text(isBrake ? "ABS pulse" : "Rev-limit buzz")
                            if isBrake { Tag(text: "Simulated", tint: .orange) }
                        }
                    }
                    if isBrake {
                        Text("ETS2 does not report ABS activity. The pulse fires on wheel slip or very hard braking instead.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if config.pulse {
                        SliderRow(title: "Pulse strength", value: $config.pulseStrength, range: 0.125...1)
                        SliderRow(title: "Pulse frequency", value: $config.pulseFrequency, range: 5...60) { "\(Int($0)) Hz" }
                    }
                }
            }
            .disabled(!config.enabled)
            if !isBrake {
                Divider()
                Toggle("Release on gear change", isOn: $config.shiftRelease)
                Text("The trigger goes slack for a moment on every shift, then its resistance builds back, like the drive being interrupted.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if config.shiftRelease {
                    SliderRow(title: "Release time", value: $config.shiftReleaseTime, range: 0.1...1) { String(format: "%.2f s", $0) }
                }
            }
            Divider()
            Meter(label: "Trigger position (live)", value: position, tint: .secondary)
            Meter(label: "Current effect", value: effect.level, tint: isBrake ? .red : .green, detail: effect.summary)
        }
    }

    private var sources: [TriggerSource] { isBrake ? [.speed, .pedal, .deceleration, .rpm] : [.rpm, .speed, .pedal] }

    private var styleNote: String {
        switch (config.style, isBrake) {
        case (.original, true): return "Resistance grows with road speed and peaks at 90 km/h."
        case (.original, false): return "The trigger vibrates faster when the engine is lugging or near the redline, and is calm in the efficient band."
        case (.custom, _): return "Resistance follows the curve below. The orange marker shows where the driving signal is now."
        }
    }
}

// MARK: - Haptics

struct HapticRow: Identifiable {
    let id: EffectPreview
    let name: String
    let detail: String
    let approximate: Bool
    let path: WritableKeyPath<HapticsConfig, HapticEffect>
}

struct HapticsStudioView: View {
    @Environment(AppModel.self) private var model

    static let original: [HapticRow] = [
        .init(id: .engineStart, name: "Engine start", detail: "Cranking kicks, then a lurch as the engine catches", approximate: false, path: \.engineStart),
        .init(id: .gearJolt, name: "Gear change", detail: "Two-frame jolt on every shift", approximate: false, path: \.gearJolt),
        .init(id: .hardBraking, name: "Hard braking", detail: "Pulsing under full brake with strong deceleration", approximate: false, path: \.hardBraking),
        .init(id: .bodyRoll, name: "Body roll", detail: "Leans into the side the truck rolls toward", approximate: false, path: \.bodyRoll),
        .init(id: .refuel, name: "Refuelling", detail: "Pump chug that fades as the tank fills", approximate: false, path: \.refuel),
        .init(id: .fineAlert, name: "Fine alert", detail: "Siren rumble for five seconds after a fine", approximate: false, path: \.fineAlert),
    ]
    static let additions: [HapticRow] = [
        .init(id: .engineIdle, name: "Engine vibration", detail: "Constant light vibration that rises with RPM", approximate: false, path: \.engineIdle),
        .init(id: .engineStop, name: "Engine stop", detail: "Short thud when the engine shuts down", approximate: false, path: \.engineStop),
        .init(id: .roadSurface, name: "Road surface", detail: "Suspension movement and loose surfaces", approximate: true, path: \.roadSurface),
        .init(id: .collision, name: "Collision", detail: "Damage increase or a sudden acceleration spike", approximate: true, path: \.collision),
        .init(id: .revLimiter, name: "Rev limiter", detail: "Buzz above 95% of the RPM limit", approximate: false, path: \.revLimiter),
        .init(id: .warning, name: "Warning pulse", detail: "Three pulses when a critical warning appears", approximate: false, path: \.warning),
    ]

    var body: some View {
        @Bindable var model = model
        PageScroll {
            Card(title: "Mixing", icon: "slider.horizontal.3") {
                Picker("When effects overlap", selection: $model.profile.haptics.mix) {
                    Text("Strongest wins").tag(MixMode.strongest)
                    Text("Add together").tag(MixMode.additive)
                }
                .pickerStyle(.segmented)
                SliderRow(title: "Master level", value: $model.profile.haptics.master)
                SliderRow(title: "Safety limit", value: $model.profile.haptics.limit)
                HStack(spacing: 16) {
                    Meter(label: "Heavy motor", value: Double(model.snap.output.rumbleLeft) / 255)
                    Meter(label: "Light motor", value: Double(model.snap.output.rumbleRight) / 255)
                }
                Text("These are the DualSense's two rumble motors. The voice-coil HD haptics a PS5 uses are an audio stream and are not driven by this app.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Card(title: "Core Effects", icon: "waveform") {
                ForEach(Self.original) { row in effectRow(row, $model.profile.haptics) }
            }
            Card(title: "Extra Effects", icon: "plus.circle") {
                ForEach(Self.additions) { row in effectRow(row, $model.profile.haptics) }
            }
        }
    }

    private func effectRow(_ row: HapticRow, _ haptics: Binding<HapticsConfig>) -> some View {
        let effect = haptics[dynamicMember: row.path]
        return HStack(spacing: 12) {
            Toggle(row.name, isOn: effect.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                HStack { Text(row.name); if row.approximate { Tag(text: "Approximation", tint: .orange) } }
                Text(row.detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 290, alignment: .leading)
            Slider(value: effect.intensity, in: 0...1) { Text("\(row.name) intensity") }.labelsHidden()
                .disabled(!effect.wrappedValue.enabled)
            Text("\(Int(effect.wrappedValue.intensity * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            Button("Preview") { model.runtime.play(row.id) }
                .disabled(model.snap.device == nil)
                .accessibilityLabel("Preview \(row.name)")
        }
    }
}

// MARK: - Lighting

struct LightingStudioView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let L = $model.profile.lighting
        PageScroll {
            Card(title: "Lightbar", icon: "light.strip.2") {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6).fill(model.snap.output.lightbarColor)
                        .frame(height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                        .accessibilityLabel("Current lightbar colour")
                }
                SliderRow(title: "Brightness", value: L.brightness)
                Text("Rules are checked top to bottom; the first one that applies sets the colour.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 12) {
                    Toggle("Fine alert", isOn: L.fineAlert).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    ruleLabel("Fine alert", "Red and blue flashing for five seconds")
                    Spacer()
                    previewButton(.fineAlert, "Fine alert")
                }
                rule("Parking brake", "Solid while the parking brake is on", L.parkBrake, .parkBrake)
                rule("Retarder", "Pulses faster at higher retarder levels", L.retarder, .retarder)
                rule("Hazard lights", "Follows the hazard flashers", L.hazard, .hazard)
                rule("Turn signal", "Follows the indicator lamp", L.blinker, .blinker)
                rule("Low fuel", "Slow pulse while the fuel warning is lit", L.lowFuel, .lowFuel)
                rule("Damage", "Chassis or engine wear above the threshold", L.damage, .damage)
                if model.profile.lighting.damage.enabled {
                    SliderRow(title: "Damage threshold", value: L.damageThreshold, range: 0.05...1).padding(.leading, 50)
                }
                rule("Braking", "Brightens with brake pressure", L.braking, .braking)
                HStack(spacing: 12) {
                    Toggle("RPM gauge", isOn: L.rpmGauge).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    ruleLabel("RPM gauge", "Green to red with engine speed")
                    Spacer()
                    previewButton(.rpmGauge, "RPM gauge")
                }
                rule("Engine running", "Base colour when nothing else applies", L.base, .base)
            }
            Card(title: "Indicators", icon: "circle.grid.3x3") {
                HStack {
                    Toggle("Fuel gauge on the player LEDs", isOn: L.fuelPlayerLEDs)
                    Spacer()
                    previewButton(.fuelGauge, "fuel gauge")
                }
                Toggle("Warnings on the microphone LED", isOn: L.warningsMicLED)
                Text("Mic LED pulses for oil pressure, coolant temperature, air pressure or heavy chassis damage; steady for AdBlue or battery warnings.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ruleLabel(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func previewButton(_ p: EffectPreview, _ name: String) -> some View {
        Button("Preview") { model.runtime.play(p) }
            .disabled(model.snap.device == nil)
            .accessibilityLabel("Preview \(name)")
    }

    private func rule(_ name: String, _ detail: String, _ rule: Binding<LightRule>, _ preview: EffectPreview) -> some View {
        HStack(spacing: 12) {
            Toggle(name, isOn: rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            ruleLabel(name, detail)
            Spacer()
            ColorPicker("\(name) colour", selection: colorBinding(rule.color), supportsOpacity: false).labelsHidden()
            previewButton(preview, name)
        }
    }
}
