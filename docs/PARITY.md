# Feature parity with ETS2_PS5_DualSense v1.5 (Windows)

Classes: **V** implemented and verified · **U** implemented, unverified · **P** partial · **B** blocked · **N** not implemented.

"Verified" below means one of: (logic) the Swift port matches the C++ port that was checked
branch-by-branch against the Windows binary and is covered by a unit test; (bytes) the encoded HID
report matches the bytes the Windows app emits; (hw) the controller accepted the report and its own
trigger-status bytes changed. **Nobody has yet confirmed by feel or by eye that an effect is right
in an actual drive** — every row is therefore at most "U" for the end-to-end experience until the
checklist in PROGRESS.md is run.

| Windows feature | Class | Evidence |
|---|---|---|
| Brake trigger resistance (L2), grows to 90 km/h | U | logic: `testOriginalBrakeTriggerScalesWithSpeed`; bytes `01 00 force`: `testUSBReportLayout`; hw: L2 status byte 0x19 -> 0x10 on continuous resistance over Bluetooth |
| Throttle trigger vibration (R2) by RPM band | U | logic: `testOriginalThrottleFrequencyBands`; bytes `26 FF 02 .. freq/2` incl. idle value 1; hw: R2 status changed for mode 0x26. Thresholds follow the current truck instead of being frozen at startup (deliberate) |
| Engine cranking + start lurch | U | `testEngineStartLurchLasts1500ms`. Primed on connect, so no spurious lurch mid-drive (deliberate difference) |
| Gear jolt | U | `testGearJoltIsTwoFrames` |
| Hard-braking rumble | U | `testHardBrakingBeatsBodyRoll` |
| Body-roll rumble | U | simulated-drive test |
| Refuel chug | U | simulated-drive test; plugin reuses RenCloud's refuel heuristic |
| Fine alert (lightbar + siren rumble, 5 s) | U | `testFineAlertFlashesFiveSeconds`. Unlike upstream, the rumble obeys its intensity slider |
| Status lightbar (park brake, retarder, hazards, indicators) | U | `testLightbarPriority`; colours are now editable |
| Fuel gauge on player LEDs | U | `testFuelGaugeAndMicLED` |
| Mic-LED master warning | U | `testFuelGaugeAndMicLED` |
| Rim steering | U | maths: `testRimSteeringFollowsStickRotation`; the game registered the input device (`Initializing device 'DualSense Rim Steering'` in game.log). Binding and driving with it not tried |
| USB output (report 0x02) | U | bytes tested; **no USB cable test has been run** |
| Bluetooth output (report 0x31 + CRC) | V (transport) | every report accepted on macOS 26.6, 0 failures, ~0.5 ms per write |
| Clean state on exit | V (quit, SIGTERM) / U (sleep, disconnect) | hw over Bluetooth: trigger status L2 0x10 / R2 0x01 while driving returned to the idle values 0x19 / 0x09 after a normal quit and after `kill -TERM`. Sleep and mid-effect disconnect paths not exercised |
| Single instance | V | `LSMultipleInstancesProhibited` |
| `.cfg` file with 17 keys and aliases | N | Replaced by JSON profiles and the UI. No importer |
| Console status display | N | Replaced by the Dashboard |
| PS button quits the app | N | Deliberately dropped; the PS button belongs to macOS/Steam here |
| Faster stick polling for rim steering | P | Stick is sampled at the 60 Hz loop rate |

## Additions (not in the Windows mod)

| Feature | Signal | Honest label |
|---|---|---|
| Custom trigger curves, min/max, dead zone, smoothing, source selection | speed, RPM, effective pedal, deceleration | telemetry |
| ABS pulse on L2 | wheel speed vs road speed, or hard-brake condition | **simulated** — ETS2 exposes no ABS channel |
| Throttle release on gear change (R2 goes slack mid-shift) | gear number change | telemetry |
| Turn signals per side on the player LEDs | indicator lamp and stalk state | telemetry |
| Rev-limit buzz on R2 / rumble | RPM > 95 % of limit | telemetry |
| Engine vibration, engine stop | RPM, engine state | telemetry |
| Road surface | suspension deflection change + surface name | approximation |
| Collision | wear increase or acceleration spike | approximation |
| Warning pulse | critical warning edge | telemetry |
| Low-fuel, damage, braking, RPM-gauge, base lightbar rules | fuel warning, wear, brake, RPM | telemetry |
| Profiles, import/export, auto-select by truck | truck brand/name/id from SDK config | telemetry |

## Not possible / out of scope

- **HD (voice-coil) haptics**: on the DualSense these are an audio stream over USB audio, not a HID
  field. Only the two rumble motors are driven. (B for parity purposes; the Windows mod does not
  use them either.)
- **True ABS state, tyre slip, surface friction**: not in the SCS SDK.
