import DualSenseKit
import EffectKit
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Binding var page: Page?

    var body: some View {
        let s = model.snap
        let t = s.truck
        PageScroll {
            if let hint = setupHint {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(hint)
                    Spacer()
                    Button("Open Game Setup") { page = .setup }
                }
                .padding(12)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(alignment: .top, spacing: 16) {
                Card(title: "Controller", icon: "gamecontroller") {
                    if let d = s.device {
                        Text(d.name).font(.title3.weight(.semibold))
                        HStack(spacing: 8) {
                            Tag(text: d.transport.rawValue, tint: .blue)
                            if d.isEdge { Tag(text: "Edge") }
                        }
                        HStack(spacing: 6) {
                            Image(systemName: batteryIcon(s.input))
                            Text(batteryText(s.input)).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Battery \(batteryText(s.input))")
                    } else {
                        Text("Not connected").font(.title3.weight(.semibold))
                        Text("Connect a DualSense over USB or pair it in Bluetooth settings.").foregroundStyle(.secondary)
                    }
                }
                Card(title: "Game", icon: "truck.box") {
                    Text(model.gameRunning ? "Running" : "Not running").font(.title3.weight(.semibold))
                    StatusLine(ok: model.games.contains { $0.status == .installed },
                               text: pluginText)
                    if !t.truckName.isEmpty && s.telemetryLive {
                        Text("\(t.truckBrand) \(t.truckName)").foregroundStyle(.secondary)
                    }
                }
                Card(title: "Telemetry", icon: "dot.radiowaves.left.and.right") {
                    Text(telemetryTitle).font(.title3.weight(.semibold))
                    Text(telemetryDetail).foregroundStyle(.secondary)
                    if model.demoMode { Tag(text: "Demo drive (simulated)", tint: .orange) }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                Card(title: "Vehicle", icon: "speedometer") {
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        BigValue(value: String(format: "%.0f", abs(t.speedKmh)), unit: "km/h", label: "Speed")
                        BigValue(value: String(format: "%.0f", t.engineRpm), unit: "rpm", label: "Engine")
                        BigValue(value: t.gearLabel, unit: "", label: "Gear")
                    }
                    Meter(label: "RPM", value: Double(t.rpmFraction), tint: t.rpmFraction > 0.9 ? .red : .accentColor,
                          detail: String(format: "%.0f / %.0f", t.engineRpm, t.engineRpmMax))
                    Meter(label: "Throttle (game)", value: Double(t.effectiveThrottle), tint: .green)
                    Meter(label: "Brake (game)", value: Double(t.effectiveBrake), tint: .red)
                    Meter(label: "Fuel", value: Double(t.fuelPercent / 100), tint: t.fuelWarning ? .orange : .accentColor)
                }
                .opacity(s.telemetryLive || model.demoMode ? 1 : 0.45)

                Card(title: "Controller Output", icon: "waveform.path") {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 5).fill(s.output.lightbarColor)
                            .frame(width: 60, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
                            .accessibilityLabel("Lightbar colour")
                        HStack(spacing: 4) {
                            ForEach(0..<5, id: \.self) { i in
                                Circle().fill(s.output.playerLEDs & (1 << i) != 0 ? Color.primary : Color.primary.opacity(0.12))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Player LEDs")
                        .accessibilityValue("\(s.output.playerLEDs.nonzeroBitCount) of 5 lit")
                        Spacer()
                        Text("Source: \(s.source)").font(.caption).foregroundStyle(.secondary)
                    }
                    Meter(label: "L2 brake trigger", value: s.output.leftTrigger.level, tint: .red, detail: s.output.leftTrigger.summary)
                    Meter(label: "R2 throttle trigger", value: s.output.rightTrigger.level, tint: .green, detail: s.output.rightTrigger.summary)
                    Meter(label: "Rumble · heavy motor", value: Double(s.output.rumbleLeft) / 255)
                    Meter(label: "Rumble · light motor", value: Double(s.output.rumbleRight) / 255)
                }
            }

            Card(title: "Active Effects", icon: "sparkles") {
                if !model.effectsEnabled {
                    Text("Effects are switched off.").foregroundStyle(.secondary)
                } else if s.active.isEmpty {
                    Text(s.telemetryLive || model.demoMode ? "Nothing active right now." : "Waiting for telemetry.").foregroundStyle(.secondary)
                } else {
                    FlowRow(items: s.active.labels)
                }
            }
        }
    }

    private var setupHint: String? {
        if model.games.isEmpty { return "No Euro Truck Simulator 2 installation was found in your Steam libraries." }
        if model.games.allSatisfy({ $0.status == .notInstalled }) { return "The telemetry plugin is not installed in the game yet." }
        if model.games.contains(where: { $0.status == .outdated }) { return "The telemetry plugin in the game is from a different app version." }
        return nil
    }

    private var pluginText: String {
        if model.games.contains(where: { $0.status == .installed }) { return "Telemetry plugin installed" }
        if model.games.contains(where: { $0.status == .outdated }) { return "Telemetry plugin needs updating" }
        return "Telemetry plugin not installed"
    }

    private var telemetryTitle: String {
        let s = model.snap
        if model.demoMode { return "Simulated" }
        if s.telemetryLive { return s.truck.paused ? "Connected · paused" : "Live" }
        return "Not connected"
    }

    private var telemetryDetail: String {
        let s = model.snap
        if model.demoMode { return "Scripted drive, not the game" }
        if s.telemetryLive { return s.truck.paused ? "Game is in a menu" : String(format: "%.0f frames/s from the game", s.framesPerSecond) }
        if model.gameRunning { return s.pluginSeen ? "Accept the SDK prompt in the game" : "Plugin has not loaded" }
        return "Start the game to begin"
    }

    private func batteryText(_ i: InputState) -> String {
        if model.snap.stats.inputReports == 0 { return "Battery unknown" }
        switch i.charge {
        case .charging: return "\(i.batteryPercent)% · charging"
        case .full: return "Fully charged"
        default: return "\(i.batteryPercent)%"
        }
    }

    private func batteryIcon(_ i: InputState) -> String {
        if i.charge == .charging || i.charge == .full { return "battery.100percent.bolt" }
        switch i.batteryPercent {
        case ..<20: return "battery.0percent"
        case ..<45: return "battery.25percent"
        case ..<70: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct BigValue: View {
    let value: String, unit: String, label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit).foregroundStyle(.secondary)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
    }
}

struct FlowRow: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { Tag(text: $0, tint: .accentColor) }
        }
    }
}
