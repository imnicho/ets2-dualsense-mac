# ETS2 DualSense for macOS — design

## Intent
Get the Windows mod [LikeARealG/ETS2_PS5_DualSense](https://github.com/LikeARealG/ETS2_PS5_DualSense) (v1.5, 17.11.2026) working on this Mac with every feature, usable immediately. Upstream ships only Windows binaries (no source), so this is a clean rewrite.

## Goals
- Feature parity with upstream v1.5: engine crank + lurch, RPM trigger vibration, gear jolt, hard-braking rumble, body-roll rumble, brake and throttle trigger resistance, fine alert (lightbar + siren rumble, 5 s), refuel pulse, player-LED fuel gauge, status lightbar (indicators/hazards/park brake/retarder), mic-LED master warning, PS button exits, rim steering (off by default).
- Same config file: same keys, aliases, defaults, auto-created next to the executable.
- Works over Bluetooth and USB.

## Non-goals
- DualSense Edge support, GUI, distribution/signing, Windows/Linux builds.
- Editing the user's Steam Input bindings or `controls_osx.sii` (rim steering setup stays manual, documented).

## Constraints
- ETS2 on Mac is x86_64 (Rosetta): the game plugin must be an x86_64 dylib in `Euro Truck Simulator 2.app/Contents/MacOS/plugins/`.
- Apple's GameController API cannot set the mic LED or individual player LEDs, so the app writes raw HID output reports (USB report 0x02; Bluetooth report 0x31 with CRC32).
- License: upstream is PolyForm Noncommercial; personal use, credit LikeARealG.

## Approaches
1. **Run the Windows exe under Wine/CrossOver** — rejected: the game is the native Mac build, so the exe's Windows shared memory can't see it, and HID access through Wine is unreliable.
2. **GameController framework** — rejected: no mic LED, no per-LED player lights.
3. **Native rewrite: own SCS SDK plugin + raw-HID companion (chosen)** — full feature coverage, no runtime dependencies beyond system frameworks.

## Design
- `plugin/` — C++ dylib (x86_64) using the SCS Telemetry + Input SDK. Writes a fixed-layout struct to a memory-mapped file; reads a steering value from a second mapped file and reports it as input device `dualsense_rim` / "DualSense Rim Steering", axis `steering`.
- `app/` — C++ terminal program (arm64). Layers: `telemetry` (map file), `dualsense` (IOKit HID in/out, USB + BT), `effects` (pure function: telemetry + time + config → controller output state; unit-testable), `config`, `ui` (status console matching upstream fields).
- Effect thresholds, frequencies and timings are taken from the upstream exe by disassembly where recoverable; anything not recoverable is my call and listed in the README.
- `tools/fake-telemetry` — writes simulated telemetry to the mapped file so effects can be tested without the game.

## Left to the builder
Mapped-file paths, struct layout, build system (plain Makefile, clang).
