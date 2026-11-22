import AppKit
import SwiftUI

@main
struct ETS2DualSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("ETS2 DualSense", id: "main") {
            RootView()
                .environment(AppModel.shared)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 720)

        MenuBarExtra {
            MenuBarView().environment(AppModel.shared)
        } label: {
            Image(systemName: AppModel.shared.snap.device == nil ? "gamecontroller" : "gamecontroller.fill")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signals: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppModel.shared.start()
        // Leave the controller neutral even when killed from a terminal or by logout.
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signals.append(source)
        }
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum Page: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case triggers = "Adaptive Triggers"
    case haptics = "Haptics"
    case lighting = "Lighting"
    case profiles = "Profiles"
    case setup = "Game Setup"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .triggers: return "l2.button.roundedtop.horizontal"
        case .haptics: return "waveform"
        case .lighting: return "lightbulb"
        case .profiles: return "person.2.crop.square.stack"
        case .setup: return "puzzlepiece.extension"
        case .diagnostics: return "stethoscope"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var page: Page? = Page(rawValue: UserDefaults.standard.string(forKey: "page") ?? "") ?? .dashboard

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $page) {
                Section {
                    ForEach([Page.dashboard]) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
                Section("Effects") {
                    ForEach([Page.triggers, .haptics, .lighting, .profiles]) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
                Section("System") {
                    ForEach([Page.setup, .diagnostics]) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { SidebarStatus().padding(12) }
        } detail: {
            Group {
                switch page ?? .dashboard {
                case .dashboard: DashboardView(page: $page)
                case .triggers: TriggerStudioView()
                case .haptics: HapticsStudioView()
                case .lighting: LightingStudioView()
                case .profiles: ProfilesView()
                case .setup: SetupView()
                case .diagnostics: DiagnosticsView()
                }
            }
            .navigationTitle((page ?? .dashboard).rawValue)
            .toolbar {
                ToolbarItem {
                    Picker("Profile", selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                        ForEach(model.profiles) { Text($0.name).tag($0.id) }
                    }
                    .help("Active profile")
                }
                ToolbarItem {
                    Toggle(isOn: $model.effectsEnabled) {
                        Label("Effects", systemImage: model.effectsEnabled ? "power.circle.fill" : "power.circle")
                    }
                    .toggleStyle(.button)
                    .help(model.effectsEnabled ? "Effects are on. Click to switch every effect off." : "Effects are off.")
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct SidebarStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusLine(ok: model.snap.device != nil,
                       text: model.snap.device.map { "Controller · \($0.transport.rawValue)" } ?? "No controller")
            StatusLine(ok: model.snap.telemetryLive, text: model.snap.telemetryLive ? (model.snap.truck.paused ? "Telemetry connected · paused" : "Telemetry live") : (model.gameRunning ? "Game running, no telemetry" : "Game not running"))
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Text(model.snap.device.map { "\($0.name) · \($0.transport.rawValue) · \(model.snap.input.batteryPercent)%" } ?? "No controller connected")
        Text(model.snap.telemetryLive ? "Telemetry: \(model.snap.source)" : "Telemetry: not connected")
        Divider()
        Toggle("Effects Enabled", isOn: $model.effectsEnabled)
        Picker("Profile", selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
            ForEach(model.profiles) { Text($0.name).tag($0.id) }
        }
        Divider()
        Button("Open ETS2 DualSense") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
