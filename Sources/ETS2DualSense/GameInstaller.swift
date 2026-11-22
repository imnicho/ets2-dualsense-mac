import AppKit
import Foundation

/// Finds installed SCS games and manages our telemetry plugin inside them.
struct GameInstall: Identifiable, Equatable {
    enum Status: Equatable { case notInstalled, installed, outdated }
    var name: String
    var appURL: URL
    var status: Status
    var id: String { appURL.path }
    var pluginURL: URL { appURL.appendingPathComponent("Contents/MacOS/plugins/\(GameInstaller.pluginName)") }
}

enum GameInstaller {
    static let pluginName = "ets2_dualsense.dylib"
    static let games = [
        ("Euro Truck Simulator 2", "Euro Truck Simulator 2/Euro Truck Simulator 2.app"),
        ("American Truck Simulator", "American Truck Simulator/American Truck Simulator.app"),
    ]
    static let executables: Set<String> = ["eurotrucks2", "amtrucks"]

    /// The plugin shipped inside the app bundle (or next to a development build).
    static var bundledPlugin: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(pluginName),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/\(pluginName)"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func steamLibraries() -> [URL] {
        // The real home directory: inside the App Sandbox the usual APIs return the container instead.
        let home = URL(fileURLWithPath: String(cString: getpwuid(getuid()).pointee.pw_dir))
        let steam = home.appendingPathComponent("Library/Application Support/Steam")
        var libraries = [steam]
        if let vdf = try? String(contentsOf: steam.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8) {
            for line in vdf.split(separator: "\n") {
                let parts = line.split(separator: "\"").map(String.init)
                if let i = parts.firstIndex(of: "path"), parts.count > i + 2 {
                    libraries.append(URL(fileURLWithPath: parts[i + 2]))
                }
            }
        }
        var seen = Set<String>()
        return libraries.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func scan() -> [GameInstall] {
        let fm = FileManager.default
        let bundled = bundledPlugin.flatMap { try? Data(contentsOf: $0) }
        var found: [GameInstall] = []
        for lib in steamLibraries() {
            for (name, rel) in games {
                let app = lib.appendingPathComponent("steamapps/common/\(rel)")
                guard fm.fileExists(atPath: app.path) else { continue }
                var g = GameInstall(name: name, appURL: app, status: .notInstalled)
                if let installed = try? Data(contentsOf: g.pluginURL) {
                    g.status = bundled == nil || installed == bundled ? .installed : .outdated
                }
                found.append(g)
            }
        }
        return found
    }

    static func install(into game: GameInstall) throws {
        guard let source = bundledPlugin else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "The plugin is missing from the app bundle."])
        }
        let dir = game.pluginURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Atomic replace: a running game keeps its already-loaded copy.
        try Data(contentsOf: source).write(to: game.pluginURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: game.pluginURL.path)
    }

    static func uninstall(from game: GameInstall) throws {
        try FileManager.default.removeItem(at: game.pluginURL)
        let dir = game.pluginURL.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func gameIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            executables.contains($0.executableURL?.lastPathComponent ?? "")
        }
    }
}
