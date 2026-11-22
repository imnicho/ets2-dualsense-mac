# Progress

Last updated 2026-11-22. Test machine: M4 Pro, macOS 26.6, DualSense (054C:0CE6) over Bluetooth,
ETS2 1.62.3.3s from Steam.

## Done

- Research on the three reference projects (`docs/research/`), licence decision (noncommercial, inherited).
- Game plugin (telemetry + rim-steering input device), shared-memory contract v2.
- DualSense layer: discovery, USB/Bluetooth encoding, input parsing, battery, hot-plug, reset.
- Effect engine: all Windows-mod effects plus additions, mixing, limits, curves.
- Profiles: 5 built-in, custom, import/export, auto-select by truck, persistence.
- SwiftUI app: Dashboard, Adaptive Triggers, Haptics, Lighting, Profiles, Game Setup, Diagnostics, menu bar item.
- Packaging: `.app` bundle with the plugin inside, DMG, ad-hoc signature.
- App icon and release DMG.
- 37 automated tests (`make test`), all passing.

## Verified, with evidence

| Claim | Evidence |
|---|---|
| Native macOS ETS2 loads SDK plugins | `game.log.txt`: `loading 'ets2_dualsense' ...plugins/ets2_dualsense.dylib`, then after accepting the SDK dialog `[ets2-dualsense] telemetry ready` and `[sdk] Initializing device 'DualSense Rim Steering' as 'dualsense_rim'` |
| Plugin -> app shared memory works across Rosetta/arm64 | `dsprobe telemetry` read `sdk=1 game=1 paused=1` from the file the game created; the app showed "Telemetry connected · paused" |
| macOS 26 accepts raw output reports over Bluetooth on a non-seized device | `dsprobe`: 7 different reports, all `kIOReturnSuccess`, 0.3–1.6 ms each; app Diagnostics: 0 failed writes |
| The triggers actually take the effects | Input-report trigger status bytes changed with each effect (L2 0x19 -> 0x10 for resistance; R2 -> 0x02 / 0x01 for feedback / vibration) and returned to idle on reset |
| Full Bluetooth input reports + battery | 0x31 reports parsed at ~66 Hz, battery level and stick/trigger values read |
| Quit and SIGTERM leave the controller neutral | status bytes back to idle values after both, measured while a trigger effect was active |
| App pipeline end to end without the game | Demo drive: Dashboard showed telemetry, trigger effects and LEDs; status bytes confirmed the controller was being driven |
| Overhead | effects queue under 3 % of samples in a 3 s profile; whole app about 7 % CPU idle-with-window and about 16 % while the Dashboard animates (SwiftUI layout); loop body ~0.8 ms including the HID write |

## Not verified yet (needs a person)

Nobody has felt or watched the controller during these tests, and the game never left its main
menu, so **live in-truck telemetry values and the physical feel of every effect are unconfirmed**.

Manual checklist:

1. **Feel test, no game** — Adaptive Triggers > Test Bench on: L2 should stiffen as Speed rises; R2 should buzz at low and high RPM and be calm in the middle. Haptics > Preview each row. Lighting > Preview each rule (lightbar colour, player LEDs, mic LED).
2. **Live telemetry** — load into a truck. Dashboard speed / RPM / gear should match the in-game dashboard; Diagnostics shows the game frame rate and telemetry age.
3. **Drive** — engine start (crank + lurch), gear changes, hard stop from 60 km/h, indicators / hazards / parking brake colours, fuel LEDs.
4. **Coexistence** — steering, buttons and triggers must still control the truck with the app running, with Steam Input on and off.
5. **Lifecycle** — unplug/disconnect mid-drive and reconnect; quit the game with effects active; sleep and wake; switch profiles while driving; toggle Effects off while braking.
6. **USB** — repeat step 1 on a cable. USB encoding is unit-tested but has never been sent to hardware.
7. **Rim steering** — bind the game's steering axis to "DualSense Rim Steering" and try it.

Use Diagnostics > Developer > Record Telemetry during step 3; the JSONL file can become a regression fixture.

## Known issues and open questions

- Simulated ABS relies on wheel-speed data that may never show slip if the game applies its own ABS; then only the hard-braking condition triggers it.
- Road-surface names from the SDK are matched by keyword (dirt, gravel, grass, ...); the real list needs a live sample.
- The roll channel sign convention for body roll was carried over from the Windows mod and not checked against the game.
- Steam Input may fight over the lightbar; behaviour unobserved.
- DualSense Edge is matched by product ID but untested.
- The battery reading moved from 55 % to 35 % within one session; unclear whether that is real drain from the tests or a coarse reading.
- `app/effects.cpp` and `app/effects.h` (the earlier C++ port) and `docs/superpowers/specs/` (the earlier CLI-only design) are superseded by the Swift code and kept only for reference.

## Next

1. Run the checklist above; fix whatever it turns up.
2. Capture a real drive and add it as a test fixture.
3. Tune the additions (road surface, collision thresholds) against real telemetry.
