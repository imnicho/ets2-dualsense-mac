# Upstream research: LikeARealG/ETS2_PS5_DualSense (Windows)

Researched 2026-11-22. Static inspection only (strings, PE parsing, `llvm-objdump -d`); nothing downloaded was executed.

Evidence tags used below:

- **BIN** = confirmed from the v1.5 binaries by disassembly / constant-pool / string inspection in this pass
- **DOC** = confirmed from upstream README, in-archive `!!!READ_ME!!!.txt`, config template text, or release notes
- **INF** = inferred (reasoning from the above, or from memory of third-party sources that were not re-read here)
- **UNV** = unverified

## 1. What upstream publishes

| Item | Finding | Tag |
|---|---|---|
| Git repo | `https://github.com/LikeARealG/ETS2_PS5_DualSense`, HEAD `3ee5b2d` (2026-11-18). Contains exactly two files: `LICENSE`, `README.md`. 27 commits, all README/license edits. | BIN/DOC |
| Source code | **None published.** No source in the repo or in any release archive. Binaries only. | DOC |
| Releases | v1.0 (2025-08-03, `ETS2_PS5_DualSense.rar`, 37,934 B), v1.3 (2026-02-18, 65,973 B), v1.4 (2026-04-25, 65,371 B), **v1.5 (2026-11-17, latest, `ETS2_PS5_DualSense_17_11_2026.rar`, 260,401 B)** | DOC |
| v1.5 rar sha256 | `56981a675975137632c6b520e2cdf8e0a4ef5cd963da1f17ef2ecb92dca9287d` | BIN |

v1.5 archive contents (RAR5):

| File | Size | Date in archive | sha256 (first 16) | What it is |
|---|---|---|---|---|
| `ETS2_PS5_Adaptive_Triggers.exe` | 106,496 | 2026-11-17 | `bbddcb4e4a953a30` | The app. PE32+ console x86-64, MSVC, dynamic CRT. PDB path `C:\_SERGIU\_GAMES\_PROIECT_PS5_ETS2\COD\ETS2_PS5_Adaptive_Triggers\x64\scs-rim-default-config\ETS2_PS5_Adaptive_Triggers.pdb`. Not packed/obfuscated. |
| `RimSteeringPlugin.dll` | 738,816 | 2026-11-17 | `ec30493ee2ee135d` | Author's own SCS **input** plugin (exports `scs_input_init`, `scs_input_shutdown`), static CRT. |
| `scs-telemetry.dll` | 42,496 | 2023-09-21 | `1d03dbc7a975e722` | RenCloud scs-sdk-plugin, unmodified-looking build (PDB `E:\RenCloud\Repository\ets2-sdk-plugin - Copy (2)\...\scs-telemetry.pdb`). Date matches RenCloud release **V.1.12.1** (2023-09-21); writes plugin revision `12` at offset 0x28. |
| `ds5w_x64.dll` | 18,944 | 2025-08-01 | `6e386b84a296edfa` | Ohjurot DualSense-Windows (DS5W) DLL (PDB `D:\Dev\cpp\github-projects\DualSense-Windows\VS19_Solution\...\ds5w_x64.pdb`). Exports include `reconnectDevice`, so it is newer than the only tagged DS5W release (v0.1-beta). |
| `!!!READ_ME!!!.txt` | 1,022 | 2026-11-17 | `6f574d963517837f` | Install + rim-steering setup. |

Note the naming drift: README says `ETS2_PS5_DualSense.exe`; the real exe is `ETS2_PS5_Adaptive_Triggers.exe` and the config is `ETS2_PS5_Adaptive_Triggers.cfg` (BIN).

## 2. Licensing

### 2.1 Upstream's own license

`LICENSE` is titled "PolyForm Noncommercial License 1.0", `Copyright (c) 2026 David Sergiu - LikeARealG`. **It is not the real PolyForm Noncommercial 1.0.0 text**; it is a short custom text using that title (GitHub classifies it as `NOASSERTION`/"Other"). Full operative terms, verbatim:

> **Acceptance** In order to receive this license, you must agree to its terms. The terms of this license are both conditions of the license and limited warranties by the licensor to you. The authors and contributors allow you to do as you wish with the software for noncommercial purposes, provided that you agree to the conditions of this license.
>
> **Noncommercial Purpose** You may use, copy, modify, and distribute this software for any noncommercial purpose. A "noncommercial purpose" is one that is not primarily intended for or directed towards commercial advantage or monetary compensation.
>
> **Attribution** You must provide attribution by including the copyright notice above and the text of this license in all copies or substantial portions of the software.
>
> **No Other Rights** This license does not grant any rights in the trademarks, service marks, or logos of the licensor.
>
> **Disclaimer** (standard MIT-style "AS IS" warranty disclaimer)

README restatement (DOC): personal use — free to use, modify, share; no selling / commercial redistribution; "If you repost or modify this, you **must** credit me (`LikeARealG`) and include the original license."

License history (BIN, from git log): no license at all from 2025-08-04 until 2026-02-26. On 2026-02-26 an MIT license (`Copyright (c) 2026 LikeARealg - David Sergiu`) was committed at 22:03:52 +0200, deleted at 22:17:01, and replaced by the current text at 22:17:56. MIT was live for ~13 minutes and the repo has never contained code, so relying on that MIT grant would be weak; treat the current license as governing.

### 2.2 Verdict for the macOS port (not legal advice)

- The port is **not a strict clean-room rewrite**: `effects.cpp` reproduces constants and control flow recovered by disassembling the exe. The safest reading is to treat it as a modified/derived version under upstream's terms rather than argue independence.
- Under upstream's terms that is **permitted**: modification and distribution are allowed for noncommercial purposes. Conditions: (1) keep it noncommercial (no selling, no paid distribution); (2) ship the copyright notice `Copyright (c) 2026 David Sergiu - LikeARealG` and the full license text with every copy; (3) credit `LikeARealG` (README requirement).
- Nothing in the license forbids reverse engineering, and there is no EULA in the archive (BIN: no such strings/files).
- Practical consequence: the port cannot be released under MIT/Apache or any license that allows commercial use unless upstream agrees. Personal use on this Mac is clearly fine.
- UNV: the custom license text is informal; ambiguities (e.g. whether "distribute" covers derived source) are untested. Asking the author (Discord `LikeARealG`) for explicit permission would remove doubt if the port is ever published.

### 2.3 Third-party components and their licenses

| Component | Ships as | License | Notes |
|---|---|---|---|
| RenCloud **scs-sdk-plugin** | `scs-telemetry.dll` | **MIT**, `Copyright (c) 2014 Hans` (verified via GitHub API) | Provides shared memory `Local\SCSTelemetry`. Upstream archive ships no MIT notice for it. |
| Ohjurot **DualSense-Windows (DS5W)** | `ds5w_x64.dll` | **MIT**, `Copyright (c) 2020 Ludwig Füchsl`, with a preamble: "Only the implementation is licensed under the MIT license. The protocol of the DualSense 5 controller has been discovered independently and collectively by several people." (verified via GitHub API; GitHub shows `NOASSERTION` only because of the preamble) | Upstream archive ships no MIT notice for it. |
| **SCS Telemetry/Input SDK** | compiled into `RimSteeringPlugin.dll` and `scs-telemetry.dll` | SCS SDK license (the port already carries `sdk/sdk_license.txt`) | UNV: not re-read in this pass. |
| MSVC runtime | dynamic (exe, ds5w, scs-telemetry) / static (RimSteeringPlugin) | Microsoft redistributable terms | Irrelevant to the port. |

The macOS port links none of these binaries. It re-implements (a) RenCloud's refuel heuristic and field semantics and (b) DS5W's output-report encoding. Both are MIT; a credit line plus the two MIT notices in the port's README/NOTICE is the conservative choice.

## 3. Feature inventory

### 3.1 Effects (README wording condensed; behaviour column is from the binary)

| # | Feature (README) | Actual behaviour in v1.5 exe | Tag |
|---|---|---|---|
| 1 | Engine cranking: rhythmic kick, right side | While `engineEnabled == 0 && rpm > 0 && rpm >= prevRpm`: on frames where `frame % 10 < 5`, right rumble >= `200 * mult` | BIN |
| 2 | Startup lurch: strong rumble, left side | On rising edge of `engineEnabled`: for 1.5 s, left rumble >= `sin(e/1.5 * pi) * 255 * mult` | BIN |
| 3 | RPM vibration on right trigger at lugging / near redline | R2 = DS5W `EffectEx`, start 0, keepEffect, **all three forces 0**, frequency byte from RPM curve (section 5.3). Only while engine enabled. | BIN |
| 4 | Gear jolt: two-stage "ka-thunk" | On gear change where neither old nor new gear is 0 (neutral): frame 1 left >= `255*mult`, right >= `100*mult`; frame 2 left >= `100*mult`, right >= `255*mult` | BIN |
| 5 | Hard braking rumble | `engineEnabled && userBrake > 0.8 && kmh > 10 && accel < -10 m/s^2`: on `frame % 6 < 3` both motors >= `255*mult` | BIN |
| 6 | Body roll rumble, same side as lean | Only if hard-braking branch did not fire, and `kmh > 10`: `roll = rotationZ * 100`; if `|roll| > 0.1`: `a = min(|roll|, 2)`, `intensity = ((a-0.1)*225/1.9 + 30) * mult`, `v = (sin(frame*0.2)+1)*0.5*intensity`; `roll > 0` -> left, else right | BIN |
| 7 | Brake trigger resistance grows with speed | L2 = DS5W `ContinuousResitance`, start 0, `force = clamp(kmh,0,90) * 200/90 * mult`. Only while engine enabled. | BIN |
| 8 | "Acceleration trigger resistance" high at both ends of RPM range, minimal in the sweet spot | Same effect as #3; there is **no resistance component** (forces are 0) — only vibration frequency varies | BIN (contradicts DOC) |
| 9 | Fine / collision alert: lightbar red/blue + alternating rumble, 5 s | Triggered by any change of telemetry `fined` byte (RenCloud toggles it per `player.fined` event). For 5 s: `phase = int(e*4) % 8`; phase 0,2 -> R=255; 4,6 -> B=255; odd phases dark. Rumble: `frame % 20 < 10` -> left >= 200 else right >= 200 (not scaled by any multiplier). Overrides all other lightbar states. | BIN |
| 10 | Refuel chugging, strong when empty, fades as tank fills | While telemetry `refuel` set: on `(frame & 15) < 8` both motors >= `mult * (255 - clamp(fuelPct,0,100)*255/100)` | BIN |
| 11 | Player-LED fuel gauge, 20% steps, blink in lower 10% of each bracket | `>80` -> 0x1F, `>60` -> 0x1B, `>40` -> 0x15, `>20` -> 0x0A, `>0.1` -> 0x04, else 0x00. Blink thresholds 90/70/50/30/10: when below, brightness = `frame % 60 < 30 ? 0 (high) : 2 (low)`. So "blink" is a bright/dim alternation at ~1 Hz, not on/off. | BIN |
| 12 | Status lightbar: indicators green, hazards yellow, park brake red, retarder blue, fines red+blue | Priority: fine > park brake (R=255) > retarder (`engineEnabled && retarderLevel != 0`: `B = (sin(frame*0.1*level)+1)*0.5*255`) > blinkers (`engineEnabled`; both lamps -> R=G=255, one -> G=255). Uses lamp state (`blinkerLeftOn/RightOn`), so it flashes with the indicator. | BIN |
| 13 | Mic LED master warning: solid = minor, pulsing = critical | critical = oil pressure \| water temp \| air pressure warning \| `wearChassis > 0.25` -> PULSE (2); minor = AdBlue \| battery voltage warning -> ON (1). Telemetry offsets 0x624/0x625/0x620/0x418 and 0x623/0x626. | BIN (field names INF from RenCloud layout) |
| 14 | Joystick rim steering (v1.5, off by default) | Section 3.4 | BIN |
| 15 | Exit with PS button | `DS5InputState.buttonsB & 1` -> send all-zero output state, free device, "Cleanup complete. Goodbye!", exit | BIN |
| 16 | DualSense Edge unsupported | README only | DOC |

Global rules (BIN):

- Rumble values combine with **max** ("raise"), never add.
- When telemetry `paused` (offset 0x4) is non-zero, the frame counter does not advance and an **all-zero** output state is sent (rumble, LEDs, lightbar, triggers all off).
- When `engineEnabled == 0`, braking/roll/trigger effects are skipped and both triggers are type 0 (off). Fine, park-brake lightbar, mic LED, fuel LEDs, refuel, gear jolt and cranking still run.
- `fuelPct = capacity > 0 ? fuel/capacity*100 : 0`; `kmh = speed*3.6`; `accel = (speed - prevSpeed) / 0.0166`.
- Previous-value state (speed, engineEnabled, rpm, gear, fined) is updated every loop iteration, paused or not, and all start at 0 — so launching the exe mid-drive fires a spurious startup lurch, and a spurious fine alert if the toggle byte happens to be 1.

### 3.2 Config file

File: `ETS2_PS5_Adaptive_Triggers.cfg` in the exe's directory (`GetModuleFileNameW`), auto-created with the template below if missing (BIN). Parser rules (BIN):

- One `key: value` per line; separator is the first `:` **or** `=`.
- Comments start at `#` or `//`; whitespace trimmed; keys lower-cased before exact-length + `memcmp` match (case-insensitive, no fuzzy match).
- Booleans: `1 / true / on / yes` and `0 / false / off / no` (case-insensitive). Anything else keeps the previous value.
- Multipliers: parsed with `strtof`; clamped to `[0, 1]`; the effect's enabled flag is `value > 0`. Unparseable values keep the default.

| Key (canonical, as written to the file) | Aliases accepted | Default | Type / range | Meaning |
|---|---|---|---|---|
| `Fine Alert (flash + rumble)` | `fine alert` | 1 | bool | Effect #9 |
| `Park Brake Lightbar` | — | 1 | bool | Red lightbar on park brake |
| `Retarder Lightbar Pulse` | `retarder lightbar` | 1 | bool | Blue pulsing lightbar |
| `Blinkers Lightbar` | `blinker lightbar` | 1 | bool | Green / yellow lightbar |
| `Warnings Mic LED` | `warning mic led` | 1 | bool | Effect #13 |
| `Fuel Player LEDs` | `fuel leds` | 1 | bool | Effect #11 |
| `Refuel Rumble` | — | 1 | float 0..1 (0 disables) | Effect #10 |
| `Gear Jolt Rumble` | `gear jolt` | 1 | float 0..1 | Effect #4 |
| `Engine Start Effects (cranking + lurch)` | `engine start effects` | 1 | float 0..1 | Effects #1, #2 |
| `Hard Braking Rumble` | `hard breaking rumble` (sic) | 1 | float 0..1 | Effect #5 |
| `Body Roll Rumble` | `body roll` | 1 | float 0..1 | Effect #6 |
| `Brake Trigger Resistance` | `left trigger resistance` | 1 | float 0..1 | Effect #7 |
| `Throttle Trigger Vibration` | `right trigger vibration` | 1 | float 0..1 | Effect #3 |
| `Rim Steering` | — | 0 | bool | Enables rim steering |
| `Rim Steering Max Degree Deviation` | — | 5 | float, finite, `>= 1` else ignored | Stick degrees per 1 degree of wheel at/above max speed; 1 = 1:1 |
| `Rim Steering Max Deviation Speed` | — | 90 | float, finite, `> 0` else ignored | km/h at which the max deviation is reached |
| `Rim Steering Lock Degrees` | — | 450 | float, accepted only in `[30, 720]` | Stick travel for full lock **to each side** (450 = 900 total) |

Template text written by the exe (DOC, from the binary's string table; column alignment as in the file):

```
# ETS2_PS5_Adaptive_Triggers config
Fine Alert (flash + rumble): 1                      # 0=OFF, 1=ON
Park Brake Lightbar: 1                              # 0=OFF, 1=ON
Retarder Lightbar Pulse: 1                          # 0=OFF, 1=ON
Blinkers Lightbar: 1                                # 0=OFF, 1=ON
Warnings Mic LED: 1                                 # 0=OFF, 1=ON
Fuel Player LEDs: 1                                 # 0=OFF, 1=ON
Refuel Rumble: 1                                    # multiplier 0.0-1.0 (0 disables)
Gear Jolt Rumble: 1                                 # multiplier 0.0-1.0 (0 disables)
Engine Start Effects (cranking + lurch): 1          # multiplier 0.0-1.0 (0 disables)
Hard Braking Rumble: 1                              # multiplier 0.0-1.0 (0 disables)
Body Roll Rumble: 1                                 # multiplier 0.0-1.0 (0 disables)
Brake Trigger Resistance: 1                         # multiplier 0.0-1.0 (0 disables)
Throttle Trigger Vibration: 1                       # multiplier 0.0-1.0 (0 disables)

# RIM STEERING - check !!!READ_ME!!!.txt
Rim Steering: 0                                     # 0=DISABLED, 1=ENABLED

Rim Steering Max Degree Deviation: <v>                # DEFAULT=5, this means how many degrees of joystick you need turn to do 1 degree of wheel turn in game. If you set this to 1 then its 1 to 1 steering
Rim Steering Max Deviation Speed: <v>                # DEFAULT=90, this means at what speed you will hit the maximum degree diviation
Rim Steering Lock Degrees: <v>                      # DEFAULT=450, this means how much you can need to turn you joystick for a full turn TO EACH SIDE (so this would be a total of 900 degrees which is default in game)
```

(The three rim numeric values are streamed with `operator<<(float)`; exact blank-line placement between sections is INF from the order of string references.)

### 3.3 Console / status UI

Startup messages (BIN strings): `Waiting for ETS2 telemetry (start the game)...`, `ETS2 telemetry not found. Make sure you copied .dll to 'plugins' folder, then start the game.`, `ETS2 telemetry found but cannot map. Ensure game is running.`, `ETS2 telemetry connected!`, `Please connect your PS5 DualSense Controller!`, `PS5 DualSense Controller found!`, `Could not open the DualSense. Retrying...`, `Telemetry + controller ready.`, `Press PS button to exit`, then `cls`. Exit: `Exiting application. Resetting controller...`, `Cleanup complete. Goodbye!`. Errors: `Lost the DualSense. Reconnect the controller and restart the app.`, `Rim steering: ` + one of `Could not create the steering publisher.` / `Rim steering is already running.` / `Could not create the steering channel.` / `Could not map the steering channel.`

Live status (cursor homed each frame, cursor hidden). Two renderers: an ASCII-art truck with a 50-column panel and ANSI colours (`[90m`, `[91m`, `[93m`), and a plain-text fallback (`Warning: Could not initialize truck UI. Falling back to plain text UI.`). Fields, in order of string use (BIN):

1. `Speed: <kmh> km/h`
2. `Accel: <a> m/s^2`
3. `Fuel : <fuel>/<capacity>L (<pct>%)`
4. `RPM  : <rpm>`
5. `Gear : <gear>   Ret: <retarder level>`
6. `Roll : <rotationZ * 57.2958> deg` (upstream display quirk: rotationZ is a 0..1 turn fraction, not radians)
7. `Blinkers: OFF | LEFT | RIGHT | HAZARDS`
8. `Fine: ON/OFF  Brake: ON/OFF  Roll: ON/OFF`
9. `Refuel: ON/OFF | LOW/OK  Eng: ON/OFF  Jolt: ON/OFF` (a low-fuel flag is computed as `fuelPct < 20`; `Eng` = cranking or lurch active)
10. `Rumble L/R: <left>/<right>`
11. `LT force: <brake force byte>  RT freq: <throttle freq byte>`

A mic-LED state string (`OFF`/`ON`/`PULSE`) and the lightbar RGB are also passed to the renderer; exact label/placement not traced (UNV).

### 3.4 Rim steering (v1.5)

Setup per `!!!READ_ME!!!.txt` (DOC): requires Steam Input enabled; set `Rim Steering: 1`; unbind steering from left stick in Steam Input "Action Set: Driving"; in `Documents\Euro Truck Simulator 2\profiles\<id>\controls.sii` set `config_lines[10]: "input j_steer \`joy2.steering\`"` and `config_lines[40]: "constant c_relatsteer 0.000000"`; in game add "DualSense Rim Steering" under Controls > Input type; set "Steering axis deadzone" to 0%.

Mechanics (BIN):

- Exe side: creates mutex `Local\ETS2_PS5_RimSteeringPublisher_v1` (single instance) and an 8-byte file mapping `Local\ETS2_PS5_RimSteering_v1`. When rim steering is on, the main loop does not sleep; it polls `getDeviceInputState` continuously until the next 16 ms deadline, publishing after every poll.
- Per sample: `x = leftStick.x`, `y = leftStick.y` (DS5W signed, -128..127, y up-positive). Engage radius 99.06, release radius 86.36 (hysteresis; i.e. 0.78 and 0.68 of 127). Inside the rim: `angle = atan2(x, y)`; if already engaged, `delta = remainder(angle - prevAngle, 2*pi)`, `ratio = min(1, |speed*3.6| / maxDeviationSpeed)` (non-finite -> 0), `steer += delta / (ratio * (maxDegreeDeviation - 1) + 1)`, clamped to `+-lock` where `lock = lockDegrees * 2*pi / 360`. Leaving the rim keeps the current steer value (no auto-centre).
- Published word (atomic xchg): `(GetTickCount64() << 21) | (lround(steer/lock * 1e6) + 1000000)`. On exit a centred value is published.
- Plugin side (`RimSteeringPlugin.dll`): `scs_input_init` accepts only version `0x10000`; registers device name `dualsense_rim`, display name `DualSense Rim Steering`, type 1 (generic), one float input `steering` / `Rim Steering Axis`. Callback: returns `SCS_RESULT_not_found` unless `first_in_frame`; `input_index = 0`; opens the mapping lazily, retry every 500 ms; value valid only if word != 0, age `< 1000 ms`, and low 21 bits `<= 2000000`; `value = (low21 - 1000000) / 1e6`, else 0.

### 3.5 Version history

| Version | Date | Notes | Tag |
|---|---|---|---|
| v1.0 | 2025-08-03 | Initial release (rumble/trigger/LED effects) | DOC |
| — | 2026-02-17 | Config file added (auto-created next to exe) | DOC |
| — | 2026-02-17 V2 | Config expanded with vibration intensity multipliers; UI changes | DOC |
| v1.3 | 2026-02-18 | Config-file bug fix | DOC |
| — | 2026-02-26 | License added (MIT for ~13 min, then "PolyForm Noncommercial") | BIN (git) |
| v1.4 | 2026-04-25 | Fixed exe not finding its dll and cfg | DOC |
| v1.5 | 2026-11-17 | Joystick rim steering mode (+ `RimSteeringPlugin.dll`) | DOC |

There is no v1.1/v1.2 release tag. Only v1.5 binaries were inspected.

## 4. Parity check against the port

Compared against `app/effects.cpp`, `app/effects.h`, `shared/ipc.h`, `plugin/plugin.cpp` as they were at the start of this pass. `shared/ipc.h` was rewritten by someone else while this research ran (paths/magic moved to `_v2`, many fields added); that newer version was not reviewed.

### 4a. Upstream has, port (these four files) lacks

1. **Config parser and template writer** — not in the reviewed files. Must implement: all aliases in 3.2 (including the misspelt `hard breaking rumble`), `:` or `=` separator, `#` and `//` comments, case-insensitive keys, the eight boolean tokens, multiplier clamp to `[0,1]`, rim range checks (`[30,720]`, `>= 1`, `> 0`), "invalid keeps default". `effects.cpp` does not clamp multipliers itself, so a value like `2` would overflow `u8()` unless the parser clamps.
2. **HID output encoding** — not in the reviewed files; exact bytes are in section 5. Easy to miss: throttle frequency byte is `max(1, freq >> 1)`, not `freq`.
3. **Exit behaviour** — PS button exit, all-zero output state on exit, centred steering word on exit.
4. **Console UI** — fields in 3.3 (port has a `Status` struct covering fine/jolt/cranking/lurch/brake/roll/refuel; it has no low-fuel flag, upstream computes `fuelPct < 20`).
5. **Single-instance guard** for the steering publisher (upstream: named mutex).
6. **Frame pacing detail** — upstream sleeps 16 ms per frame with rim steering off (real period is 16 ms plus work, and Windows timer granularity), and uses a strict 16 ms deadline with continuous stick polling when rim steering is on. The port's "one 16 ms frame" should poll the stick faster than the effect frame when rim steering is on.
7. **Controller-loss handling** — upstream only detects a lost controller when rim steering is on (input read failure is ignored otherwise); message then exit.

### 4b. Port contradicts upstream docs or binary

No contradiction with the binary was found in the effect maths; every branch of `effects_step` and `rim_step` was matched against the disassembly. Deliberate or notable differences:

1. **Throttle RPM thresholds** — upstream computes `low = (rpmMax-550)*0.2+550` and `high = (rpmMax-550)*0.7+550` **once, before the main loop**, then uses live `rpmMax` only for the top-end scaling. The port recomputes per frame (already noted in a code comment). Consequence upstream: if the exe starts before a truck is loaded (`rpmMax == 0`), thresholds stick at 440/165 and the effect degenerates into a ramp from 165 rpm to redline with no low-rpm lugging band; changing truck does not update them. The port's behaviour is arguably what upstream intended, but it is not identical.
2. **`effects_prime`** — the port seeds previous values on connect; upstream starts them at 0 and so fires a spurious 1.5 s lurch (and possibly a fine alert) when launched mid-drive. Port deviates on purpose.
3. **README vs both** — README claims the throttle trigger has *resistance* at both ends of the rev range. Binary and port agree there is none (forces 0, frequency only). README is wrong, not the port.
4. **README "blink"/"breathe"** for fuel LEDs — binary and port both alternate brightness high/low; the LEDs never turn off.
5. **Fine trigger source** — port plugin toggles `fined` on `player.fined`; RenCloud's DLL does the same (`xor byte [..+0x10d0], 1`). Match.

### 4c. Port constants independently confirmed from the binary

All values below were read from the exe's code or constant pool at the point of use (CONFIRMED-from-binary unless noted).

| Port constant / behaviour | Binary evidence |
|---|---|
| Hard braking: `userBrake > 0.8`, `kmh > 10`, `accel < -10`, `frame % 6 < 3`, `255 * mult` | `0x1400090c2..0x140009144`: f32 0.8, 10, -10; magic-divide by 6; cmp 3 |
| Accel divisor `0.0166`, `kmh = speed * 3.6` | f32 0.0166 at `0x140015330`, 3.6 at `0x140015398` |
| Brake trigger: clamp 0..90 km/h, `* 200 / 90 * mult`, continuous resistance from position 0 | `0x140009155..0x14000918d`: `mov word [state+0x0a], 0x0001`; f32 90, 200 |
| Throttle: idle 550, factors 0.2 / 0.7, low-band peak 200, high-band peak 255 | `0x140008575..0x1400085a6` and `0x14000919a..0x140009326`: f32 550, 0.2, 0.7, 200, 255 |
| Throttle trigger effect = EffectEx, start 0, keepEffect, forces 0 | `mov dword [state+0x11], 0x00010026; mov word [state+0x15], 0` |
| Fine alert 5 s, `int(e*4) % 8`, phases 0/2 red, 4/6 blue, rumble 200 alternating on `frame % 20 < 10` | `0x140008aa9..0x140008b58`: f32 5, 4; `and 0x80000007`; `0xc8` |
| Engine lurch 1.5 s, `sin(e/1.5*pi)*255*mult` on left; cranking `frame % 10 < 5`, `200*mult` on right, condition `!engine && rpm > 0 && rpm >= prevRpm` | `0x140008ec9..0x1400090a5`: f32 1.5, 3.14159, 200 |
| Gear jolt weak 100 / strong 255, two frames, neutral excluded | `0x140008e11..0x140008ec5`; f32 100, 255 |
| Body roll: `rotationZ*100`, deadband 0.1, cap 2, `(a-0.1)*225/1.9+30`, `sin(frame*0.2)`, `roll > 0` -> left | `0x1400091d4..0x1400092a2`: f64 100; f32 0.1, 2, 225, 1.9, 30, 0.2 |
| Refuel: `(frame & 15) < 8`, `mult*(255 - pct*255/100)` | `0x140008d7c..0x140008e0e` |
| Player LED masks 0x1f/0x1b/0x15/0x0a/0x04, thresholds 80/60/40/20/0.1, blink below 90/70/50/30/10, `frame % 60 < 30 ? 0 : 2` | `0x140008ca1..0x140008d78`; table bytes `00 04 0a 15 1b 1f` |
| Mic LED: critical (3 warnings or `wearChassis > 0.25`) -> 2, minor (2 warnings) -> 1 | `0x140008c30..0x140008c9e`; f32 0.25 |
| Lightbar priority and colours; retarder `(sin(frame*0.1*level)+1)*0.5*255` on blue | `0x140008b68..0x140008c23` |
| Paused -> nothing computed, zero state sent; prev-values updated regardless | `0x140008982`, `0x140009606..0x14000962b` |
| Rim: radii 86.36 / 99.06, `atan2(x, y)`, `remainder(.., 2*pi)`, ratio/deviation formula, clamp to lock, `lock = deg*2*pi/360` | `0x1400086fe..0x140008819`, `0x140007e4d` |
| Steering word `(ms << 21) | (lround(n*1e6) + 1000000)`; plugin decode: mask `0x1fffff`, `<= 2000000`, stale after 1000 ms, reopen every 500 ms, `first_in_frame` gating | exe `0x14000882f..0x14000885d`; `RimSteeringPlugin.dll` `0x180007130..0x180007260` |
| Device ids `dualsense_rim` / `DualSense Rim Steering` / `steering` / `Rim Steering Axis`, generic type, input API v1.00 | `RimSteeringPlugin.dll` `0x1800072b0..` and strings |
| Config defaults: rim off, 450 / 5 / 90, all bools on, all multipliers 1.0 | `0x1400042f1..0x14000434d`: `0x43e10000`, `0x40a00000`, `0x42b40000`, `0x01010101`, `0x3f800000` |
| Refuel heuristic in `plugin.cpp` (rising fuel with `last > 0` sets, falling clears, every 11th frame count equal samples, 5 equal -> clear) | `scs-telemetry.dll` `0x1800018cd..0x180001977` |
| `fined` toggles per event | `scs-telemetry.dll` `0x180001a68`: `xor byte [r9+0x10d0], 1` |

CONFIRMED-from-docs only: none needed — every documented behaviour that the port implements was also located in the binary.

UNVERIFIED / inferred:

- Mapping of RenCloud offsets to names (0x61e parkBrake, 0x620 airPressureWarning, 0x623 adblueWarning, 0x624 oilPressureWarning, 0x625 waterTemperatureWarning, 0x626 batteryVoltageWarning, 0x628 engineEnabled, 0x62c/0x62d blinkerLeftOn/RightOn, 0x6c retarderBrake, 0x1f8 gear, 0x2c0 fuelCapacity, 0x2e4 engineRpmMax, 0x3b4 speed, 0x3b8 engineRpm, 0x3c4 userBrake, 0x3e8 fuel, 0x418 wearChassis, 0x8c0 rotationZ, 0x10d0 fined, 0x10d4 refuel) is from memory of RenCloud's rev-12 struct, not re-read from its source here. It is internally consistent (zone starts, ordering, and the DLL's own writes to 0x10d0/0x10d4/0x628 agree). INF.
- That `rotationZ` equals SCS `world_placement.orientation.roll` (what the port's plugin stores). INF from RenCloud naming.
- How the DualSense physically renders mode 0x26 with zero strength bytes (section 5.4). INF.

## 5. Raw DualSense output encoding (what DS5W sends)

All from disassembly of `ds5w_x64.dll` (`setDeviceOutputState` at RVA 0x1de0, buffer builder at 0x1160, trigger encoder at 0x1200, CRC at 0x12a0) plus the exe's writes into `DS5OutputState`. BIN unless noted.

### 5.1 `DS5OutputState` as filled by the exe (24 bytes)

| Offset | Field | Values the exe writes |
|---|---|---|
| 0 | leftRumble | 0..255 |
| 1 | rightRumble | 0..255 |
| 2 | microphoneLed | 0 off, 1 on, 2 pulse |
| 3 | disableLeds | always 0 |
| 4 | playerLeds.bitmask | 0x00, 0x04, 0x0a, 0x15, 0x1b, 0x1f |
| 5 | playerLeds.playerLedFade | always 0 |
| 6 | playerLeds.brightness | 0 (high) or 2 (low) |
| 7,8,9 | lightbar r,g,b | 0..255 |
| 10..16 | leftTriggerEffect (type + 6 param bytes) | `00..` or `01 00 <force>` |
| 17..23 | rightTriggerEffect | `00..` or `26 00 01 00 00 00 <freq>` |

The whole struct is zeroed at the top of every frame.

### 5.2 Report layout

"p[n]" = payload byte n. USB: report byte = p[n-1] shifted by 1 (report[0] = 0x02, report[1+n] = p[n]), total **48 bytes**. Bluetooth: report[0] = 0x31, report[1] = 0x02, report[2+n] = p[n], CRC32 little-endian at report[74..77].

| Payload offset | USB report index | Value |
|---|---|---|
| p[0x00] | 1 | `0xFF` (valid_flag0) |
| p[0x01] | 2 | `0xF7` (valid_flag1) |
| p[0x02] | 3 | rightRumble |
| p[0x03] | 4 | leftRumble |
| p[0x08] | 9 | mic LED (0/1/2) |
| p[0x0A..0x14] | 11..21 | **right trigger** block (11 bytes: mode + 10 params) |
| p[0x15..0x1F] | 22..32 | **left trigger** block |
| p[0x26] | 39 | `0x03` (valid_flag2) |
| p[0x29] | 42 | `0x02` (lightbar setup; `0x01` if disableLeds, never used by the exe) |
| p[0x2A] | 43 | player LED brightness (0 high, 2 low) |
| p[0x2B] | 44 | player LED bitmask `| 0x20` (0x20 = no fade; exe always has fade off) |
| p[0x2C..0x2E] | 45..47 | lightbar R, G, B |
| everything else | | 0 (buffer is `memset` before each build) |

Bluetooth specifics: DS5W seeds its CRC with `0xEADA2D49` and hashes report bytes 0..73 (loop: 2 iterations x 37 bytes) using a table with the complement folded in (first entries `0xd202ef8d, 0xa505df1b`), storing the result at report[74..77] little-endian. Checked numerically in this pass by running DS5W's extracted table against Python's `zlib.crc32`: the result is **identical to standard CRC-32 (zlib) of the byte `0xA2` followed by report bytes 0..73**. So on macOS: `crc = crc32(0xA2 || report[0..73])`, written LE at 74..77. DS5W passes a 547-byte length to `WriteFile` on Bluetooth; the meaningful report is 78 bytes (INF: send 78 on macOS). DS5W sets report[1] = `0x02` and no sequence number.

### 5.3 Trigger effect encoding

DS5W type -> raw block (b[0] = mode byte):

| DS5W `TriggerEffectType` | Type value | Raw bytes |
|---|---|---|
| NoResitance | 0x00 | `b[0..2] = 00 00 00` (rest already 0) |
| ContinuousResitance | 0x01 | `b[0]=0x01, b[1]=startPosition, b[2]=force` |
| SectionResitance | 0x02 | `b[0]=0x02, b[1]=startPosition, b[2]=endPosition` |
| EffectEx | 0x26 | `b[0]=0x26, b[1]=0xFF - startPosition, b[2]=0x02 if keepEffect, b[4]=beginForce, b[5]=middleForce, b[6]=endForce, b[9]=max(1, frequency >> 1)` |
| Calibrate | 0xFC | `b[0]=0xFC` |

What the exe actually uses:

- **L2 / brake** (USB report bytes 22..32), engine on and `Brake Trigger Resistance > 0`:
  `01 00 FF' 00 00 00 00 00 00 00 00` where `FF'` = `(uint8)(clamp(kmh,0,90) * 200/90 * mult)` (0..200).
- **R2 / throttle** (USB report bytes 11..21), engine on and `Throttle Trigger Vibration > 0`:
  `26 FF 02 00 00 00 00 00 00 QQ 00` where `QQ = max(1, F >> 1)` and `F = (uint8)(mult * v)`:
  - `rpm <= low`: `v = 200 - (clamp(rpm, 550, low) - 550) * 200 / (low - 550)` (200 if `low == 550`)
  - `low < rpm < high`: `v = 0` -> `QQ = 1`
  - `rpm >= high`: `v = (clamp(rpm, high, rpmMax) - high) * 255 / (rpmMax - high)` (0 if `rpmMax == high`)
  So `QQ` ranges 1..100 at idle-lugging and 1..127 at redline; in the sweet spot it is 1, not 0.
- **Either trigger off** (engine off, paused, multiplier 0, or app exit): 11 zero bytes (mode 0x00).

Float-to-byte conversion everywhere is C truncation (`cvttss2si`) then low 8 bits.

### 5.4 Interpretation note (INF)

Under the commonly documented DualSense trigger protocol, mode 0x26 is the "vibration" effect: bytes 1–2 are a 10-bit active-zone mask, bytes 3–6 pack a 3-bit strength per zone, byte 9 is frequency in Hz. DS5W's EffectEx fills these as if they were start position / keep flag / three forces. With the exe's values the mask is `0x2FF` (zones 0–7 and 9) and every strength field is 0 (the lowest level), which would explain a faint buzz whose pitch tracks RPM and no added resistance. This is recalled from community protocol notes, not verified here; to be bit-identical with upstream just emit the bytes in 5.3.

## 6. Surprises worth knowing

1. The upstream "PolyForm Noncommercial" license is a home-made short text, not the real PolyForm licence; and the repo was briefly MIT.
2. No source exists anywhere upstream; the repo is README + LICENSE only.
3. The throttle "resistance" feature in the README does not exist in the binary — it is frequency-only vibration with zero force bytes, and it idles at frequency byte 1 rather than off.
4. Throttle RPM thresholds are frozen at app start (bug-prone when started from the main menu).
5. Upstream fires a spurious engine-start lurch if launched while the engine is already running.
6. Fine-alert rumble (200) ignores every intensity multiplier.
7. Upstream redistributes two MIT-licensed DLLs without their licence notices.
8. The roll readout in the UI multiplies a turn-fraction by 57.2958 and labels it degrees.

## 7. Reproducing this research

- Clone: `<scratch>/upstream-win`
- Release + extracted files: `<scratch>/upstream-win-release` (`extracted/` inside; unpacked with `bsdtar`, RAR5)
- Disassembly listings: `<scratch>/dis` (`xcrun llvm-objdump -d --x86-asm-syntax=intel`)
- Helper scripts (PE import/string dump, constant annotator): `<scratch>/tools`

The scratchpad is session-temporary; re-download if it has been cleaned.
