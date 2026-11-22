# ETS2 DualSense for macOS

Adaptive triggers, rumble and LED feedback for a PS5 DualSense in the native macOS version of
Euro Truck Simulator 2 (American Truck Simulator is detected too). A macOS reimplementation of
[LikeARealG/ETS2_PS5_DualSense](https://github.com/LikeARealG/ETS2_PS5_DualSense) with a SwiftUI
app, profiles and extra effects. No Windows, Wine or CrossOver involved.

This is an early preview. Status: [docs/PROGRESS.md](docs/PROGRESS.md) ·
Comparison with the Windows mod: [docs/PARITY.md](docs/PARITY.md).

## How it works

```
ETS2 (x86_64, Rosetta)                         ETS2 DualSense.app (arm64)
  plugins/ets2_dualsense.dylib   mmap file     TelemetryReader -> EffectEngine -> DualSenseManager
  (SCS Telemetry SDK 1.01)  -->  /tmp/...  --> (60 Hz)            (profiles)      (IOKit HID, USB/BT)
```

The plugin uses the official SCS Telemetry SDK. The app opens the controller non-exclusively and
writes raw HID output reports, so the game and Steam keep receiving input.
More in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requirements

- Apple Silicon Mac, macOS 15 or later (developed and tested on macOS 26.6)
- DualSense (USB or Bluetooth). DualSense Edge is detected but untested.
- Euro Truck Simulator 2 from Steam

## Install

1. Download the DMG from the [releases page](https://github.com/imnicho/ets2-dualsense-mac/releases)
   and drag **ETS2 DualSense** to Applications.
2. Connect the controller and open the app. It should appear on the Dashboard with its battery level.
3. Go to **Game Setup** and click **Install**. This copies the telemetry plugin to
   `Euro Truck Simulator 2.app/Contents/MacOS/plugins/`.
4. Start the game from Steam and accept the "advanced SDK features" prompt (shown every launch).
5. Drive. Pick or edit a profile in the app; changes apply immediately.

To remove everything: **Game Setup > Remove**, delete the app, and optionally
`~/Library/Application Support/ETS2DualSense/`.

No permissions are requested, and the game and Steam keep receiving controller input while the
app runs.

## Build from source

Needs Xcode 16+ command line tools. No third-party dependencies.

```
make test    # unit tests
make app     # build/ETS2 DualSense.app (plugin bundled inside)
make dmg     # build/ETS2-DualSense-<version>.dmg
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Dashboard says "Plugin has not loaded" while the game runs | The plugin was installed after the game started: restart the game. Look for `[ets2-dualsense] telemetry ready` in `~/Library/Application Support/Euro Truck Simulator 2/game.log.txt`. |
| "Accept the SDK prompt in the game" | The game is waiting on its confirmation dialog. |
| Controller not found | Bluetooth: it must show as connected in System Settings. USB: use a data cable. Diagnostics > Log shows connection events. |
| Triggers stay stiff after a crash | Reopen the app and quit it, or Diagnostics > Developer > Reset Controller. Normal quit, sleep, disabling effects and SIGTERM/SIGINT all reset the controller. |
| Lightbar flickers between two colours | Steam Input is also writing it. Disable Steam's lightbar setting for the controller, or turn off lighting rules here. |
| Steam update removed the plugin | Game Setup > Install again. |
| Writes fail with "exclusive access" | Another tool has seized the controller (e.g. a hidapi-based utility). Quit it. |

## Licence and credits

Noncommercial use only; see [LICENSE](LICENSE). The effect design (which effects exist, their
thresholds and timings) is by **LikeARealG**; this project reimplements that behaviour for macOS
and is offered under the same terms. SCS SDK headers in `sdk/` are (C) SCS Software.
Provenance of everything reused is recorded in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#provenance).
