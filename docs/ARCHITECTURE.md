# Architecture

## Modules

| Path | What | Notes |
|---|---|---|
| `plugin/plugin.cpp` | Game plugin (x86_64 dylib) | SCS Telemetry SDK 1.01 + Input SDK 1.00. Channel callbacks fill a private struct; once per frame it is copied into a memory-mapped file under a sequence lock. Also registers the "DualSense Rim Steering" input device. |
| `shared/ipc.h` | Shared-memory contract | Fixed-width fields only, identical layout on x86_64 and arm64. Imported into Swift as the `CTelemetry` module. |
| `Sources/DualSenseKit` | Controller layer | `Reports.swift`: pure encoding/decoding (USB 0x02, Bluetooth 0x31 + CRC32, trigger effect packings, input parsing). `DualSenseManager.swift`: IOHIDManager discovery, hot-plug, input callback, timed writes, reset. |
| `Sources/EffectKit` | Logic, no UI | `TruckState`/`TelemetryReader` (normalised telemetry, seqlock read, re-map on stale file), `EffectEngine` (telemetry + profile -> `OutputState`), `Profile`/`ProfileStore`, `TelemetrySimulator` (scripted drive), `EffectPreview` (clips behind the Preview buttons), `RimSteering`. |
| `Sources/ETS2DualSense` | SwiftUI app | `Runtime` (60 Hz loop on its own queue), `AppModel` (observable state, persistence, logging), `GameInstaller` (Steam library scan, plugin install), views. |
| `Sources/dsprobe` | CLI | Hardware proof of concept and telemetry dump: `dsprobe`, `dsprobe read`, `dsprobe telemetry [watch]`. |

## Data flow and threading

- **Game thread** (inside ETS2): SDK callbacks -> `publish()` -> mmap file. No locks, no syscalls per frame besides the clock.
- **HID thread**: IOHIDManager run loop; device attach/detach and input reports (state kept under a lock).
- **Effects queue** (serial, user-interactive): strict 60 Hz timer. Each tick reads telemetry, steps the engine, writes one HID report if the state changed (or once a second as keep-alive), and every 6th tick posts a snapshot to the main thread. When nothing is live it does the work on every 6th tick only.
- **Main thread**: SwiftUI only. It never touches HID or the mmap file.

`EffectEngine` is a value type with no I/O, stepped at a fixed frame interval because the Windows
mod expresses its timings in 16 ms frames. All tests drive it directly.

## Decisions

- **Official SDK plugin, not memory reading.** The native macOS game loads `.dylib` plugins from
  `Contents/MacOS/plugins/` (verified, see PROGRESS). The game is x86_64, so the plugin is too;
  the SDK headers do not compile for arm64.
- **Raw HID, not GameController.framework.** Apple's API has no mic LED, player-LED or raw trigger
  mode access. `IOHIDDeviceSetReport` on a non-seized device works over Bluetooth on macOS 26.6
  (verified) and leaves input flowing to the game.
- **Send on change + 1 s keep-alive** keeps Bluetooth traffic low and re-asserts LEDs if another
  writer (Steam) changes them.
- **Idle means hands off.** With no telemetry, in a game menu, or with effects disabled, the app
  sends one reset report (triggers off, motors off, LEDs released to the firmware) and then stays
  silent.
- **Profiles instead of the Windows `.cfg`.** The 17 config keys map onto the "Original" profile's
  fields; built-in profiles are immutable and editing one forks a custom copy.

## Provenance

| What | Source | How it is used |
|---|---|---|
| Effect behaviour and constants ("original" paths in `EffectEngine`, rim steering, refuel heuristic use) | `ETS2_PS5_Adaptive_Triggers.exe` v1.5 by LikeARealG, read by disassembly; no upstream source exists | Reimplemented; licence inherited (see LICENSE). Details in `docs/research/upstream-windows.md`. |
| Refuel detection heuristic | RenCloud scs-sdk-plugin rev 12 (MIT) | Reimplemented in `plugin.cpp`. |
| SCS SDK headers (`sdk/`) | SCS Software, MIT-style | Unmodified. |
| DualSense report layout and trigger packings | Public protocol knowledge (Linux `hid-playstation`, DS5W), cross-checked against dualsensectl-macos | Independent implementation; **no code copied** from dualsensectl-macos (GPL-3.0). |
| UI ideas (menu bar item, L2/R2 cards) | ps5-mac-companion (MIT) | Ideas only, no code. Its raw-HID path was found to be malformed; see `docs/research/macos-dualsense-projects.md`. |
