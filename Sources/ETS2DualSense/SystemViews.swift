import DualSenseKit
import EffectKit
import SwiftUI

// MARK: - Profiles

struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: Profile?
    @State private var newName = ""
    @State private var deleting: Profile?

    var body: some View {
        @Bindable var model = model
        PageScroll {
            Card(title: "Profiles", icon: "person.2.crop.square.stack") {
                ForEach(model.profiles) { p in
                    HStack(spacing: 12) {
                        Image(systemName: p.id == model.selectedID ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(p.id == model.selectedID ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(p.name).fontWeight(p.id == model.selectedID ? .semibold : .regular); if p.builtIn { Tag(text: "Built-in") } }
                            Text(summary(p)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Duplicate") { model.duplicate(p) }
                            Button("Export…") { model.exportProfile(p) }
                            if !p.builtIn {
                                Button("Rename…") { newName = p.name; renaming = p }
                                Divider()
                                Button("Delete…", role: .destructive) { deleting = p }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Actions for \(p.name)")
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(p.id) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(p.id == model.selectedID ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { model.select(p.id) }
                    if p.id != model.profiles.last?.id { Divider() }
                }
                HStack {
                    Button("Import…") { model.importProfile() }
                    Button("New from Current") { model.duplicate(model.profile) }
                }
                Text("Changing a setting while a built-in profile is active creates an editable copy automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card(title: "Automatic Selection", icon: "wand.and.stars") {
                Toggle("Switch profile when the truck changes", isOn: $model.autoProfiles)
                if model.profile.builtIn {
                    Text("Select a custom profile to give it a truck match.").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Use \"\(model.profile.name)\" for trucks containing")
                        TextField("e.g. scania", text: $model.profile.truckMatch).frame(width: 180)
                    }
                }
                if model.snap.telemetryLive, !model.snap.truck.truckId.isEmpty {
                    Text("Current truck: \(model.snap.truck.truckBrand) \(model.snap.truck.truckName) (\(model.snap.truck.truckId))")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .alert("Rename Profile", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let renaming { model.rename(renaming, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete \"\(deleting?.name ?? "")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Profile", role: .destructive) { if let deleting { model.delete(deleting) }; deleting = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func summary(_ p: Profile) -> String {
        let haptics = Mirror(reflecting: p.haptics).children.compactMap { $0.value as? HapticEffect }.filter(\.enabled).count
        var parts = ["Brake: \(p.brake.enabled ? (p.brake.style == .original ? "classic" : "custom") : "off")",
                     "Throttle: \(p.throttle.enabled ? (p.throttle.style == .original ? "classic" : "custom") : "off")",
                     "\(haptics) haptic effects"]
        if !p.truckMatch.isEmpty { parts.append("auto: \(p.truckMatch)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Game setup

struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PageScroll {
            Card(title: "Telemetry Plugin", icon: "puzzlepiece.extension") {
                Text("The game shares live telemetry through a small plugin that uses the official SCS Telemetry SDK. It is copied into the game's plugins folder; nothing else in the game is changed.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.games.isEmpty {
                    Text("No supported game was found in your Steam libraries.")
                }
                ForEach(model.games) { g in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).fontWeight(.medium)
                            StatusLine(ok: g.status == .installed, text: statusText(g.status)).font(.caption)
                        }
                        Spacer()
                        if g.status != .notInstalled { Button("Remove") { model.uninstallPlugin(g) } }
                        if g.status != .installed {
                            Button(g.status == .outdated ? "Update" : "Install") { model.installPlugin(g) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                if GameInstaller.bundledPlugin == nil {
                    Label("The plugin file is missing from this build.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            Card(title: "First Launch", icon: "list.number") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Install the plugin above, then start the game from Steam.")
                    Text("2. The game shows \"Request to use advanced SDK features detected\". Choose OK. It asks on every launch.")
                    Text("3. Drive. This window shows live telemetry as soon as you are in the truck.")
                }
                Text("If the game was already running when you installed or updated the plugin, restart it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card(title: "Playing With Steam Input", icon: "arrow.left.arrow.right") {
                Text("This app opens the controller without taking it over, so the game and Steam keep receiving every button and stick. Steam may also write the lightbar; this app re-sends its state once a second, so its colours win while effects are running and Steam's return when they stop.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Card(title: "Rim Steering", icon: "steeringwheel") {
                Toggle("Steer by rotating the left stick around its rim", isOn: $model.profile.rim.enabled)
                Group {
                    SliderRow(title: "Steering lock", value: $model.profile.rim.lockDegrees, range: 30...720) { "\(Int($0))°" }
                    SliderRow(title: "Speed damping", value: $model.profile.rim.maxDegreeDeviation, range: 1...10) { String(format: "%.1f×", $0) }
                    SliderRow(title: "Full damping at", value: $model.profile.rim.maxDeviationSpeed, range: 30...130) { "\(Int($0)) km/h" }
                }
                .disabled(!model.profile.rim.enabled)
                Text("Off by default. In the game's controller options, bind the steering axis to the \"DualSense Rim Steering\" device. Push the stick to its edge and rotate it like a wheel.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusText(_ s: GameInstall.Status) -> String {
        switch s {
        case .installed: return "Plugin installed"
        case .outdated: return "Plugin differs from this app's version"
        case .notInstalled: return "Plugin not installed"
        }
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let s = model.snap
        PageScroll {
            HStack(alignment: .top, spacing: 16) {
                Card(title: "Controller Link", icon: "cable.connector") {
                    row("Device", s.device.map { "\($0.name)" } ?? "none")
                    row("Transport", s.device?.transport.rawValue ?? "–")
                    row("Serial", s.device.map { $0.serial.isEmpty ? "not reported" : $0.serial } ?? "–")
                    row("Input reports", "\(s.stats.inputReports)")
                    row("Output reports", "\(s.stats.reportsSent) sent, \(s.stats.sendFailures) failed")
                    row("Last write", s.stats.reportsSent == 0 ? "–" : DualSenseManager.describe(s.stats.lastResult))
                    row("Trigger status", String(format: "L2 0x%02X · R2 0x%02X", s.input.leftTriggerStatus, s.input.rightTriggerStatus))
                }
                Card(title: "Timing", icon: "timer") {
                    row("Telemetry age", !s.pluginSeen ? "–" : (s.telemetryAgeMs > 2000 ? "no frames (menu or stopped)" : String(format: "%.0f ms", s.telemetryAgeMs)))
                    row("Game frame rate", String(format: "%.0f /s", s.framesPerSecond))
                    row("Effect loop", String(format: "%.1f Hz", s.tickRate))
                    row("Loop time", String(format: "%.0f µs (max %.0f)", s.tickMicros, s.maxTickMicros))
                    row("HID write", String(format: "%.0f µs (max %.0f)", s.stats.lastSendMicros, s.stats.maxSendMicros))
                    row("Telemetry → controller", s.telemetryLive && !s.truck.paused
                        ? String(format: "≈ %.1f ms", s.telemetryAgeMs + (s.tickMicros + s.stats.lastSendMicros) / 1000 + 8) : "–")
                    Text("Estimate: age of the frame, plus half a loop period, plus compute and write time.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Card(title: "Telemetry", icon: "list.bullet.rectangle") {
                row("Source", s.source)
                row("Plugin file", s.pluginSeen ? TelemetryReader.defaultPath : "not present")
                row("SDK active / live", "\(s.sdkActive ? "yes" : "no") / \(s.telemetryLive ? "yes" : "no")")
                if model.developerMode {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 3) {
                        ForEach(rawTelemetry(s.truck), id: \.0) { k, v in
                            HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) }
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            if model.developerMode {
                Card(title: "Output Report", icon: "number") {
                    Text(hex(OutputReport.encode(s.output, transport: s.device?.transport ?? .usb)))
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    row("Effects", s.active.isEmpty ? "none" : s.active.labels.joined(separator: ", "))
                }
            }
            Card(title: "Developer", icon: "hammer") {
                Toggle("Developer mode", isOn: $model.developerMode)
                if model.developerMode {
                    Toggle("Demo drive (simulated telemetry, no game needed)", isOn: $model.demoMode)
                    HStack {
                        Button(model.isRecording ? "Stop Recording" : "Record Telemetry…") { model.toggleRecording() }
                            .disabled(!model.isRecording && !s.telemetryLive)
                        Button("Reset Controller") { model.runtime.park() }
                        Text("Recordings are JSON lines, one telemetry frame each.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Card(title: "Log", icon: "text.alignleft") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.log.reversed()) { e in
                            HStack(alignment: .top, spacing: 8) {
                                Text(e.time, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                                Text(e.message).textSelection(.enabled)
                            }
                            .font(.caption.monospaced())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 180)
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.log.map { "\($0.time.formatted(.iso8601)) \($0.message)" }.joined(separator: "\n"), forType: .string)
                }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func rawTelemetry(_ t: TruckState) -> [(String, String)] {
        func f(_ v: Float) -> String { String(format: "%.3f", v) }
        func b(_ v: Bool) -> String { v ? "1" : "0" }
        return [
            ("paused", b(t.paused)), ("engineEnabled", b(t.engineEnabled)), ("electricEnabled", b(t.electricEnabled)),
            ("speed m/s", f(t.speed)), ("engineRpm", f(t.engineRpm)), ("engineRpmMax", f(t.engineRpmMax)),
            ("gear", "\(t.gear)"), ("displayedGear", "\(t.displayedGear)"),
            ("inputThrottle", f(t.inputThrottle)), ("effectiveThrottle", f(t.effectiveThrottle)),
            ("inputBrake", f(t.inputBrake)), ("effectiveBrake", f(t.effectiveBrake)), ("inputSteering", f(t.inputSteering)),
            ("cruiseControl", f(t.cruiseControl)), ("parkBrake", b(t.parkBrake)), ("motorBrake", b(t.motorBrake)),
            ("retarder", "\(t.retarderLevel)/\(t.retarderSteps)"), ("airPressure", f(t.airPressure)),
            ("brakeTemperature", f(t.brakeTemperature)), ("fuel", f(t.fuel)), ("fuelCapacity", f(t.fuelCapacity)),
            ("fuelWarning", b(t.fuelWarning)), ("refuel", b(t.refuel)), ("fined", b(t.fined)),
            ("blinker L/R", "\(b(t.blinkerLeftOn))/\(b(t.blinkerRightOn))"), ("hazard", b(t.hazardWarning)),
            ("lightBrake", b(t.lightBrake)), ("airWarn/emergency", "\(b(t.airPressureWarning))/\(b(t.airPressureEmergency))"),
            ("oil/water/battery", "\(b(t.oilPressureWarning))/\(b(t.waterTemperatureWarning))/\(b(t.batteryVoltageWarning))"),
            ("adblueWarning", b(t.adblueWarning)), ("wear chassis", f(t.wearChassis)), ("wear engine", f(t.wearEngine)),
            ("wear total", f(t.totalWear)), ("cargoMass", f(t.cargoMass)), ("trailer", b(t.trailerConnected)),
            ("accel x/y/z", "\(f(t.accelX)) \(f(t.accelY)) \(f(t.accelZ))"),
            ("roll", String(format: "%.5f", t.roll)), ("pitch", String(format: "%.5f", t.pitch)),
            ("wheels", "\(t.wheelCount)"), ("substances", Array(Set(t.wheelSubstance)).sorted().joined(separator: ",")),
            ("susp[0]", t.wheelSuspDeflection.first.map(f) ?? "–"), ("wheel rps[0]", t.wheelAngularVelocity.first.map(f) ?? "–"),
        ]
    }
}
