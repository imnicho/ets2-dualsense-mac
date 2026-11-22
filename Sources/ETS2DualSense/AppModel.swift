import AppKit
import DualSenseKit
import EffectKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct LogEntry: Identifiable {
    let id: Int
    let time: Date
    let message: String
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let runtime = Runtime()
    private let store = ProfileStore()
    private var saveTask: Task<Void, Never>?
    private var housekeeping: Timer?
    private var lastTruckId = ""
    private var logCounter = 0
    private var recorder: FileHandle?

    var snap = Snapshot()
    var log: [LogEntry] = []
    var games: [GameInstall] = []
    var gameRunning = false
    var custom: [Profile] = []
    var selectedID = Profile.original.id
    var errorMessage: String?

    var effectsEnabled = UserDefaults.standard.object(forKey: "effectsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(effectsEnabled, forKey: "effectsEnabled"); runtime.set(enabled: effectsEnabled) }
    }
    var developerMode = UserDefaults.standard.bool(forKey: "developerMode") {
        didSet {
            UserDefaults.standard.set(developerMode, forKey: "developerMode")
            if !developerMode { demoMode = false; stopRecording() }
        }
    }
    var autoProfiles = UserDefaults.standard.object(forKey: "autoProfiles") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoProfiles, forKey: "autoProfiles") }
    }
    var demoMode = false { didSet { runtime.set(demo: demoMode) } }
    var isRecording: Bool { recorder != nil }

    var profiles: [Profile] { Profile.builtIns + custom }

    /// The active profile. Editing a built-in one forks it into a custom copy.
    var profile: Profile {
        get { profiles.first { $0.id == selectedID } ?? .original }
        set {
            guard newValue != profile else { return }
            if let i = custom.firstIndex(where: { $0.id == newValue.id }) {
                custom[i] = newValue
            } else {
                var copy = newValue
                copy.id = UUID()
                copy.builtIn = false
                copy.name = uniqueName(newValue.name + " (Custom)")
                custom.append(copy)
                selectedID = copy.id
                append("Created \"\(copy.name)\" from a built-in profile")
            }
            profileChanged()
        }
    }

    private init() {
        let doc = store.load()
        custom = doc.custom
        selectedID = doc.selected
        if !profiles.contains(where: { $0.id == selectedID }) { selectedID = Profile.original.id }
    }

    func start() {
        runtime.onSnapshot = { s in Task { @MainActor in AppModel.shared.receive(s) } }
        runtime.onLog = { m in Task { @MainActor in AppModel.shared.append(m) } }
        runtime.set(profile: profile)
        runtime.set(enabled: effectsEnabled)
        if UserDefaults.standard.bool(forKey: "demo") { developerMode = true; demoMode = true } // launch with: -demo YES
        refreshGames()
        runtime.set(gameRunning: gameRunning)
        runtime.start()
        housekeeping = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.refreshGames() }
        }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared.append("Sleeping: controller reset"); AppModel.shared.runtime.park() }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared.append("Woke up"); AppModel.shared.runtime.resend() }
        }
        append("Started")
    }

    func shutdown() {
        stopRecording()
        saveNow()
        runtime.shutdown()
    }

    private func receive(_ s: Snapshot) {
        let wasLive = snap.telemetryLive, hadDevice = snap.device
        snap = s
        if s.telemetryLive != wasLive { append(s.telemetryLive ? "Telemetry connected" : "Telemetry lost") }
        if s.device != hadDevice, let d = s.device { append("Using \(d.name) (\(d.transport.rawValue))") }
        if s.telemetryLive, s.truck.truckId != lastTruckId {
            lastTruckId = s.truck.truckId
            if !s.truck.truckId.isEmpty {
                append("Truck: \(s.truck.truckBrand) \(s.truck.truckName)")
                if autoProfiles, let match = profiles.first(where: { $0.matches(s.truck) }), match.id != selectedID {
                    select(match.id)
                    append("Auto-selected profile \"\(match.name)\"")
                }
            }
        }
        if let recorder, s.telemetryLive, !s.truck.paused, let line = try? JSONEncoder().encode(s.truck) {
            recorder.write(line + Data("\n".utf8))
        }
    }

    func append(_ message: String) {
        logCounter += 1
        log.append(LogEntry(id: logCounter, time: Date(), message: message))
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    // MARK: profiles

    private func profileChanged() {
        runtime.set(profile: profile)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { self?.saveNow() }
        }
    }

    private func saveNow() {
        do { try store.save(.init(selected: selectedID, custom: custom)) }
        catch { append("Could not save profiles: \(error.localizedDescription)") }
    }

    private func uniqueName(_ base: String) -> String {
        var name = base, n = 2
        while profiles.contains(where: { $0.name == name }) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        profileChanged()
    }

    func duplicate(_ p: Profile) {
        var copy = p
        copy.id = UUID()
        copy.builtIn = false
        copy.truckMatch = ""
        copy.name = uniqueName(p.name + " Copy")
        custom.append(copy)
        select(copy.id)
    }

    func delete(_ p: Profile) {
        guard !p.builtIn else { return }
        custom.removeAll { $0.id == p.id }
        if selectedID == p.id { selectedID = Profile.original.id }
        profileChanged()
    }

    func rename(_ p: Profile, to name: String) {
        guard let i = custom.firstIndex(where: { $0.id == p.id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        custom[i].name = name
        profileChanged()
    }

    func exportProfile(_ p: Profile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(p.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ProfileStore.export(p).write(to: url) } catch { errorMessage = error.localizedDescription }
    }

    func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var p = try ProfileStore.importProfile(Data(contentsOf: url))
            p.name = uniqueName(p.name)
            custom.append(p)
            select(p.id)
        } catch {
            errorMessage = "That file is not a valid profile. (\(error.localizedDescription))"
        }
    }

    // MARK: game

    func refreshGames() {
        let scanned = GameInstaller.scan()
        if scanned != games { games = scanned }
        let running = GameInstaller.gameIsRunning()
        if running != gameRunning {
            gameRunning = running
            runtime.set(gameRunning: running)
            append(running ? "Game is running" : "Game is not running")
        }
    }

    func installPlugin(_ g: GameInstall) {
        do {
            try GameInstaller.install(into: g)
            append("Installed the telemetry plugin into \(g.name)")
            if gameRunning { append("Restart the game to load the plugin") }
        } catch { errorMessage = "Could not install the plugin: \(error.localizedDescription)" }
        refreshGames()
    }

    func uninstallPlugin(_ g: GameInstall) {
        do {
            try GameInstaller.uninstall(from: g)
            append("Removed the telemetry plugin from \(g.name)")
        } catch { errorMessage = "Could not remove the plugin: \(error.localizedDescription)" }
        refreshGames()
    }

    // MARK: recording (developer mode)

    func toggleRecording() {
        if recorder != nil { stopRecording(); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "telemetry-\(Int(Date().timeIntervalSince1970)).jsonl"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        recorder = try? FileHandle(forWritingTo: url)
        append(recorder == nil ? "Could not open \(url.lastPathComponent)" : "Recording telemetry to \(url.lastPathComponent)")
    }

    func stopRecording() {
        guard let recorder else { return }
        try? recorder.close()
        self.recorder = nil
        append("Recording stopped")
    }
}
