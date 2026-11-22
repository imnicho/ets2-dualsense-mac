# macOS DualSense reference projects: findings

Researched 2026-11-22. Both repos were cloned read-only and neither was built or run.

- `alfaoz/dualsensectl-macos` at `02dc1d5` (2026-03-20)
- `cestercian/ps5-mac-companion` at `d226836` (2026-04-30)

Evidence labels used throughout:

- **[code]** read directly in the repo at the cited file:line.
- **[docs]** claimed by the repo's README / CHANGELOG / comments, not verified by me.
- **[inferred]** my reasoning or background knowledge (hidapi, Linux `hid-playstation`), not stated in either repo.

Nothing here was tested on hardware.

---

## 1. Summary

| | dualsensectl-macos | ps5-mac-companion |
|---|---|---|
| License | GPL-3.0 (`LICENSE`), `main.c` SPDX `GPL-3.0-or-later`, `crc32.h` SPDX `GPL-2.0-or-later` | MIT, "Copyright (c) 2026 Cestercian" |
| Language / build | C11, single `main.c` (1990 lines) + `crc32.h`; `Makefile.macos` or meson; depends on Homebrew `hidapi` | Swift 5.9, SwiftPM (`Package.swift`) plus XcodeGen `project.yml` and a generated `.xcodeproj`; macOS 13+ |
| Activity | 2 commits by the porter, both 2026-03-20; rest is upstream `nowrep/dualsensectl` history | 11 commits, 2026-04-29 to 2026-04-30; nothing since |
| Stars / forks | 2 / 0 | 2 / 1 |
| Issues | 0 issues, 0 PRs | 0 issues, 1 open PR |
| HID approach | hidapi (IOKit backend) for all I/O; IOHIDManager only for hotplug monitoring | IOHIDManager raw HID and GameController.framework in parallel |
| Tested on (per README) | macOS Sequoia (15), arm64, USB and BT | macOS 13, 14, 26.4 |
| Usefulness | Correct, complete protocol reference for output reports and trigger packing | UI and lifecycle ideas only; its raw HID layer is defective |

The single most useful artefact is the trigger packing in `dualsensectl-macos/main.c:832-1074`. The single most important warning is that ps5-mac-companion's headline claim ("macOS 26 blocks third-party trigger and lightbar writes") is not established for raw HID, because its raw HID writes are malformed (section 4.2).

---

## 2. Licensing

### 2.1 dualsensectl-macos: GPL-3.0

- `LICENSE` is the GPLv3 text. **[code]**
- `main.c:1` is `SPDX-License-Identifier: GPL-3.0-or-later`; `meson.build:5` says `GPL-3.0-or-later`. **[code]**
- `crc32.h:1` is `GPL-2.0-or-later`. **[code]**
- Upstream (`nowrep/dualsensectl`) was `GPL-2.0-or-later` with a GPLv2 `LICENSE`; the port commit `b354cdc` swapped the LICENSE file to GPLv3 and changed the SPDX line. That relicensing is permitted by "or later". **[code, from `git show d3ae2fa:LICENSE` and the diff]**
- `main.c:5` carries "Copyright (c) 2020 Sony Interactive Entertainment": the structs and flag names descend from the Linux `hid-playstation` driver. **[code]** for the header, **[inferred]** for the lineage.
- `main.c:7` reads "macOS port by @anthropic/claude-code", so the macOS delta is AI-generated. **[code]**

Consequences if you copy code from it:

- Your distributed app becomes a derivative work and must be licensed GPL-3.0 (or GPL-2.0-or-later if you take the equivalent code from upstream instead), with full source, the licence text, and preserved copyright notices.
- GPL is incompatible with PolyForm Noncommercial. GPL forbids adding further restrictions, and a noncommercial clause is one. You cannot ship one work that contains both GPL code and PolyForm-NC code.

### 2.2 ps5-mac-companion: MIT

- Standard MIT text, "Copyright (c) 2026 Cestercian". **[code]**
- Copying is allowed into a project under any licence, including GPL, PolyForm-NC, or a permissive one.
- Required attribution: keep the copyright line and the full permission notice in copies or substantial portions. A `THIRD_PARTY_NOTICES` file or a header on the derived file satisfies this.

### 2.3 Interaction with a PolyForm-Noncommercial behavioural reference

- If you only reproduce behaviour (what the upstream tool does for each telemetry condition) and copy none of its code, text, or assets, the PolyForm-NC licence does not attach to your code and you can choose your own licence. **[inferred, general copyright principle, not legal advice]**
- If you copy any PolyForm-NC code, those portions stay PolyForm-NC. That is source-available, not open source in the OSI sense, and it rules out including any GPL code.
- Protocol facts (report IDs, byte offsets, mode numbers, bit packings) are not copyrightable expression. Reimplementing them in Swift from a description is not copying. **[inferred, not legal advice]**

---

## 3. dualsensectl-macos: the low-level layer

All references are to `dualsensectl-macos/main.c` unless stated.

### 3.1 Architecture

A one-shot CLI: parse args, open the device, build one output report with exactly one feature's valid-flag set, send, exit. The only long-running mode is `monitor`. There is no state kept between invocations.

The port's diff against upstream is 150 lines in `main.c`: header includes, a `nanosleep` shim (`:39-42`), extra input-length branches in `command_battery` (`:498-519`), a suppressed serial warning (`:421-428`), and an IOHIDManager-based `command_monitor` (`:1106-1203`). Everything else is upstream Linux code. **[code]**

### 3.2 Opening the device

- All device I/O goes through hidapi, not IOHIDManager: `hid_enumerate` (`:377`, `:381`), `hid_open(vendor, product, serial)` (`:412`). **[code]**
- VID `0x054c`, PIDs `0x0ce6` (DualSense) and `0x0df2` (Edge) (`:44-46`). **[code]**
- `hid_init` is never called explicitly and `hid_darwin_set_open_exclusive` is never called. **[code, by grep]**
- hidapi on macOS opens devices exclusively by default (`kIOHIDOptionsTypeSeizeDevice`) since 0.12.0 unless `hid_darwin_set_open_exclusive(0)` is called. Confirmed in the locally installed header `/opt/homebrew/include/hidapi/hidapi_darwin.h:51-68`. So this tool seizes the controller for the few milliseconds each command runs. **[inferred from hidapi, not from the repo]**
- Implication: its "works on Sequoia over BT and USB" result was obtained with a seized handle. It is not evidence that a non-seized handle can write output reports.
- IOHIDManager appears only in `monitor`: `IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone)` (`:1152`), two matching dicts of `kIOHIDVendorIDKey` + `kIOHIDProductIDKey` (`:1163-1171`) set with `IOHIDManagerSetDeviceMatchingMultiple` (`:1176`), matching and removal callbacks (`:1178-1179`), scheduled on the current run loop (`:1181`), `IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone)` (`:1183`), then `CFRunLoopRun()` (`:1191`). No seize there. **[code]**

### 3.3 USB vs Bluetooth detection

- `ds->bt = dev->interface_number == -1` (`:438`), same test in the device list (`:1745`). hidapi reports `-1` for non-USB devices. **[code]**
- In `monitor`, the serial comes from `kIOHIDSerialNumberKey`, normalised from `aa-bb-..` to `AA:BB:..` (`:1109-1128`). **[code]**
- On macOS over USB the serial is often missing; the code falls back to `00:00:00:00:00:00` (`:421-428`). So serial is not a reliable device identity on USB. **[code]**
- For a native IOHIDManager app, `kIOHIDTransportKey` is the direct equivalent (ps5-mac-companion does this, section 4.2). **[inferred]**

### 3.4 Output reports

Constants (`:53-60`, `:72`):

| | USB | Bluetooth |
|---|---|---|
| Report ID | `0x02` | `0x31` |
| Total length including report ID | 63 | 78 |
| Header after ID | none | byte 1 = `seq << 4` (low nibble flags = 0), byte 2 = tag `0x10` |
| Common payload starts at | byte 1 | byte 3 |
| Trailer | none | CRC32 little-endian in bytes 74..77 |

- Structs: `dualsense_output_report_bt` (`:221-231`), `dualsense_output_report_usb` (`:233-239`), 47-byte common block asserted at `:219`. **[code]**
- Sequence: 4-bit counter in the high nibble, incremented per report and wrapped at 16 (`:314-316`). Because the CLI is one-shot, it is always 0 in practice. **[code]**
- CRC: `crc32_le(0xFFFFFFFF, &seed, 1)` with seed `0xA2`, continued over bytes 0..73, then bitwise inverted (`:340-347`). Table and routine in `crc32.h`. This is standard reflected CRC-32 (poly `0xEDB88320`) over `[0xA2] + report[0..<74]`. **[code]**
- Send: `hid_write(ds->dev, report->data, report->len)` (`:350`). **[code]**
- hidapi's macOS `hid_write` calls `IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, data[0], data, length)`, passing the buffer with the report ID still in byte 0 and the full length (63 or 78). **[inferred from hidapi, not in this repo]**
- Every command zeroes the whole report and sets only the valid flags for the one feature it changes (`:306`, `:326`). Nothing else is touched on the controller.

Common payload offsets (0-based within the 47-byte block, from the struct at `:178-218`):

| Offset | Field |
|---|---|
| 0 | `valid_flag0` |
| 1 | `valid_flag1` |
| 2 | `motor_right` |
| 3 | `motor_left` |
| 4 | headphone volume |
| 5 | speaker volume |
| 6 | internal mic volume |
| 7 | `audio_flags` |
| 8 | `mute_button_led` |
| 9 | `power_save_control` |
| 10 | right trigger mode |
| 11..20 | right trigger params (10) |
| 21 | left trigger mode |
| 22..31 | left trigger params (10) |
| 32..35 | host timestamp |
| 36 | `reduce_motor_power` |
| 37 | `audio_flags2` |
| 38 | `valid_flag2` |
| 39 | `haptics_flags` |
| 40 | reserved |
| 41 | `lightbar_setup` |
| 42 | `led_brightness` |
| 43 | `player_leds` |
| 44, 45, 46 | lightbar R, G, B |

### 3.5 Adaptive trigger effects

Mode bytes (`:133-139`): off `0x05`, feedback `0x21`, bow `0x22`, galloping `0x23`, weapon `0x25`, vibration `0x26`, machine `0x27`.

`command_trigger` (`:832-870`) writes the same mode and params into both trigger slots and uses the valid flags to pick which one the controller applies: `valid_flag0` bit 2 for right, bit 3 for left (`:838-843`). Only `param[0..8]` are ever written; `param[9]` is always 0.

Below, `p0..p8` are the nine parameter bytes after the mode byte. "zone mask" means a 16-bit little-endian value in `p0` (low) and `p1` (high).

| Effect | Mode | Packing | Accepted ranges | Lines |
|---|---|---|---|---|
| off | `0x05` | all params 0 | none | `:872-875` |
| feedback | `0x21` | zone array, see below; `p8 = 0` | position 0..9, strength 1..8 | `:904-920` |
| feedback-raw | `0x21` | zone array from 10 explicit strengths; `p8 = 0` | each 0..8 | `:1066-1069` |
| vibration | `0x26` | zone array; `p8 = frequency` | position 0..9, amplitude 1..8, frequency > 0 | `:1043-1064` |
| vibration-raw | `0x26` | zone array from 10 explicit amplitudes; `p8 = frequency` | each 0..8 | `:1071-1074` |
| weapon | `0x25` | zone mask = `(1<<start) \| (1<<end)`; `p2 = strength - 1` | start 2..7, end start+1..8, strength 1..8 | `:922-943` |
| bow | `0x22` | zone mask = `(1<<start) \| (1<<end)`; `p2 = ((strength-1)&7) \| (((snap-1)&7) << 3)` | start 1..8, end start+1..8, strength 1..8, snap 1..8 | `:945-971` |
| galloping | `0x23` | zone mask = `(1<<start) \| (1<<end)`; `p2 = (second_foot&7) \| ((first_foot&7) << 3)`; `p3 = frequency` | start 0..8, end start+1..9, first 0..6, second first+1..7, frequency > 0 | `:973-1007` |
| machine | `0x27` | zone mask = `(1<<start) \| (1<<end)`; `p2 = (strength_a&7) \| ((strength_b&7) << 3)`; `p3 = frequency`; `p4 = period` | start 1..8, end start+1..9, strengths 0..7, frequency > 0 | `:1009-1041` |
| raw numeric | any | mode and `p0..p8` taken verbatim from argv, no checks | none | `:1965-1976` |

Zone-array packing (`trigger_bitpacking_array`, `:877-902`), used by feedback and vibration:

- Ten zones, index 0..9, each with a strength 0..8 where 0 means inactive.
- `active_zones` (16 bit): bit `i` set if zone `i` has strength > 0.
- `strength_zones` (32 bit): for each active zone, `((strength - 1) & 7) << (3 * i)`. Thirty bits used.
- `p0 = active_zones & 0xff`, `p1 = active_zones >> 8`
- `p2..p5 = strength_zones` little-endian
- `p6 = 0`, `p7 = 0`
- `p8 = frequency` (0 for feedback)

The simple `feedback POS STRENGTH` and `vibration POS AMP FREQ` forms just fill zones `POS..9` with one value (`:914-917`, `:1058-1061`).

Worked example, `feedback 3 6`: zones 3..9 active, mask `0x03F8`, each strength field `5`, so `strength_zones = 0x2DB6DA00`. Params `F8 03 00 DA B6 2D 00 00 00` after mode `0x21`. **[inferred, computed by hand from the code above]**

Notes:

- Error-message text disagrees with the checks in a few places (bow says "between 0 and 8" but rejects 0 at `:947`; galloping says "0 and 8" for limits of 6 and 7 at `:983-990`). The checks are what count.
- Galloping prints a hint that frequency works better below 8 (`:996-998`).
- Machine has a comment that start 0 does nothing (`:1011`).

### 3.6 Lightbar, LEDs, rumble, attenuation

| Feature | Valid flag | Payload | Lines |
|---|---|---|---|
| Lightbar RGB | `valid_flag1` bit 2 (`0x04`) | R, G, B each scaled by `brightness / 255` in software | `:610-626` |
| Lightbar on / off | `valid_flag2` bit 1 (`0x02`) | `lightbar_setup` = 1 (on) or 2 (fade out) | `:589-608` |
| LED brightness | `valid_flag2` bit 0 (`0x01`) | `led_brightness` 0..2 | `:628-645` |
| Player LEDs | `valid_flag1` bit 4 (`0x10`) | `player_leds` = pattern, plus bit 5 (`0x20`) for instant (no fade) | `:647-675` |
| Mic mute LED | `valid_flag1` bit 0 (`0x01`) | `mute_button_led` 0 off, 1 on, 2 pulse | `:698-719` |
| Mic mute | `valid_flag1` bit 1 (`0x02`) | `power_save_control` bit 4 | `:677-696` |
| Motor / trigger attenuation | `valid_flag1` bit 6 (`0x40`) | `reduce_motor_power = (rumble & 7) \| ((trigger & 7) << 4)` | `:817-830` |
| Right trigger | `valid_flag0` bit 2 (`0x04`) | mode + params at 10..20 | `:838-840` |
| Left trigger | `valid_flag0` bit 3 (`0x08`) | mode + params at 21..31 | `:841-843` |

Player LED patterns (`:649-658`), bit 0 is the leftmost LED:

| Index | Bits |
|---|---|
| 0 | `0b00000` |
| 1 | `0b00100` |
| 2 | `0b01010` |
| 3 | `0b10101` |
| 4 | `0b11011` |
| 5 | `0b11111` |
| 6 | `0b10001` |
| 7 | `0b01110` |

Rumble is **not implemented** in this tool. `motor_right` / `motor_left` exist in the struct (`:183-184`) and the flags `COMPATIBLE_VIBRATION` (`valid_flag0` bit 0), `HAPTICS_SELECT` (`valid_flag0` bit 1) and `COMPATIBLE_VIBRATION2` (`valid_flag2` bit 2) are defined (`:79-80`, `:99`), but no command sets them. You need the Linux `hid-playstation` driver as the reference for rumble. **[code]**

The attenuation comment at `:823` notes the two nibbles cannot be changed independently without knowing the current value; a stateful app does not have that problem.

### 3.7 Input report and battery parsing

Input struct at `:155-175`. Offsets within the struct:

| Struct offset | Field |
|---|---|
| 0..3 | left X, left Y, right X, right Y |
| 4, 5 | L2, R2 analogue |
| 6 | sequence number |
| 7..10 | buttons (4 bytes) |
| 11..14 | reserved |
| 15..20 | gyro X, Y, Z (16-bit each) |
| 21..26 | accel X, Y, Z |
| 27..30 | sensor timestamp |
| 31 | reserved |
| 32..39 | two touch points, 4 bytes each |
| 40..51 | reserved |
| 52 | status: low nibble battery level, high nibble charging state |
| 53..62 | reserved |

Absolute position of the struct inside the raw buffer:

- USB report `0x01`, 64 bytes: struct starts at byte 1, so status is byte 53 (`:496-497`). **[code]**
- BT report `0x31`, 78 bytes: struct starts at byte 2, so status is byte 54; last 4 bytes are CRC, which is not checked (`:509-512`). **[code]**

Battery decode (`:524-556`):

- Charging nibble 0: discharging, percent = `min(level * 10 + 5, 100)`
- 1: charging, same formula
- 2: full, 100
- `0xa`, `0xb`: not charging (voltage / temperature fault), 0
- `0xf` and anything else: unknown, 0

macOS-only branches added by the port (`:498-508`): USB length 63 parsed from byte 0, and BT lengths 73 or 77 parsed from byte 1, with comments saying "macOS IOKit strips report ID". This contradicts ps5-mac-companion's comment that the IOKit input-report callback delivers the buffer with the report ID in byte 0, "confirmed empirically by hex-dumping" (`ps5-mac-companion/Sources/DualSenseMac/HID/InputReport.swift:38-41`). The stripped branches look speculative; the standard branches would handle the with-ID case. Dispatch on the `reportID` callback argument and on length rather than assuming either. **[inferred]**

BT full-report mode:

- The tool never reads feature report `0x05`. `DS_FEATURE_REPORT_CALIBRATION` is defined (`:62-63`) and unused. **[code, by grep]**
- If it receives a BT report of 10 bytes or fewer it prints "Battery reading requires USB connection on macOS (Bluetooth only provides simple reports)" and fails (`:514-518`). That is the simple `0x01` BT report, and it contradicts the README table saying BT battery works. **[code]**
- So this tool relies on something else having already switched the controller to `0x31` mode. On macOS that is probably the system's own GameController driver reading calibration at connect time. **[inferred]**
- For your app: read feature report `0x05` (41 bytes) once on BT connect, and treat a short `0x01` report as "not yet in full mode". **[inferred, standard practice from hid-playstation]**

Other feature reports used: `0x20` firmware info, 64 bytes (`:563-587`); `0x08` BT control for power-off with CRC seed `0x53` (`:455-479`); `0x09` pairing info is defined only.

### 3.8 macOS-specific notes and caveats

- README states testing on Sequoia arm64 only (`README.md:15`). No mention of macOS 26, Input Monitoring, Steam, or GameController conflicts. **[docs]**
- README feature table claims lightbar, player LEDs, all trigger modes and mic LED work over both BT and USB (`README.md:17-31`). **[docs]**
- Speaker, volume and mic control are listed as USB only and described as a hardware limitation (`README.md:33`). **[docs]**
- USB serial number often unavailable through IOKit (`:423`). **[code comment]**
- No permission handling anywhere. **[code]**
- Zero issues and zero PRs on GitHub, so no field reports either way.

---

## 4. ps5-mac-companion: UI and controller management

Paths are relative to `ps5-mac-companion/Sources/DualSenseMac/`.

### 4.1 Architecture

- `App/DualSenseMacApp.swift`: `@main`, a `MenuBarExtra` with `.window` style plus a `WindowGroup(id: "settings")` (`:43-60`).
- `App/AppState.swift`: one `@MainActor ObservableObject` holding connection state, latest input, and the profile. Profile `didSet` saves to disk and schedules an output push (`:10-28`).
- `HID/`: `DualSenseManager` (IOHIDManager), `HIDDevice` (per-device read/write), `InputReport`, `OutputReport`, `GameControllerBridge`.
- `Protocol/`: small `Codable` value types per feature.
- `Persistence/`: one `Profile` struct saved as JSON.
- `Notifications/NotificationWatcher.swift`: polls the Notification Center SQLite DB (needs Full Disk Access). Unrelated to your use case.

### 4.2 HID approach: both, with the raw path broken

Raw IOKit:

- `IOHIDManagerCreate(..., kIOHIDOptionsTypeNone)`, matching dict `kIOHIDVendorIDKey` / `kIOHIDProductIDKey` as `NSNumber` (`HID/DualSenseDevice.swift:24-32`). The comment says a bare `UInt32` in `[String: Any]` does not bridge reliably into the matching dictionary. PID `0x0CE6` only, no Edge.
- Scheduled on the main run loop (`:33`).
- `IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone)`, explicitly not seized, with the comment "seize blocks GameController.framework from writing" (`:57-60`).
- After open, also walks `IOHIDManagerCopyDevices` in case the matching callback does not fire for already-attached devices (`:64-73`). This can call `handleMatched` twice for the same device. **[inferred]**
- Transport from `kIOHIDTransportKey` containing "bluetooth" (`:93-102`).
- Input via `IOHIDDeviceRegisterInputReportCallback` with a 64 or 78 byte buffer (`HID/HIDDevice.swift:26-41`).
- Output via `IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, base, data.count)` (`HID/HIDDevice.swift:44-58`).

Defects in the raw path:

1. The buffer passed to `IOHIDDeviceSetReport` is the bare 47-byte payload with no report ID in byte 0 (`HID/OutputReport.swift:38-39`, `App/AppState.swift:177-178`). hidapi, which is known to work, passes the report ID as the first byte of the buffer as well as in the argument. The whole payload is therefore very likely shifted by one byte on the wire. **[inferred]**
2. Only a USB encoder exists. The same 47-byte USB buffer with ID `0x02` is sent over Bluetooth: no `0x31`, no sequence/tag, no CRC (`App/AppState.swift:177-178`). BT output cannot work through this path. **[code]**
3. `valid_flag0 = 0xFF` and `valid_flag1 = 0x57` are sent on every write (`HID/OutputReport.swift:42`, `:53`). Against the flag definitions in dualsensectl that enables headphone, speaker and mic volume control with zero volumes, power-save control, and motor attenuation. The inline comment calls bit 6 "LED brightness control"; dualsensectl defines it as vibration attenuation. **[code + inferred]**
4. It writes `0x07` at offset 39 and leaves 38 at 0, calling 39 "the actual valid_flag2" (`HID/OutputReport.swift:70-74`). In the Linux layout `valid_flag2` is 38 and 39 is `haptics_flags`. This is consistent with an off-by-one against the reference it copied from. **[inferred]**
5. Trigger encoding (`Protocol/TriggerEffect.swift:42-96`) uses mode `0x00` for off, and for `0x21`, `0x25`, `0x26` writes plain start / end / strength bytes with strengths scaled to 0..255 (`:100-103`). That does not match the bit-packed formats in section 3.5. The plain-byte layout resembles the older simple modes `0x01` / `0x02` / `0x06`, not these mode numbers. **[code + inferred]**
6. Input parsing only accepts `data[0] == 0x01` with at least 55 bytes (`HID/InputReport.swift:42-46`). A BT `0x31` report is rejected, and the short BT `0x01` report is too small. So input and battery over Bluetooth do not work through this parser even though the README says they do. **[code]**
7. The 30 Hz keepalive rewrites the full report forever (`App/AppState.swift:131-138`); comments in the same block say both "5 Hz" and "30 Hz".
8. The device-removal callback ignores which device was removed (`HID/DualSenseDevice.swift:48-56`, `:87-91`). Single-controller only.
9. `HIDDevice` passes itself unretained to the callback and is replaced on each match, so a second match frees the first while its callback registration is cleared only in `deinit` (`HID/HIDDevice.swift:20-24`). Fragile.

GameController.framework (`HID/GameControllerBridge.swift`):

- Observes `GCControllerDidConnect` / `DidDisconnect`, also scans `GCController.controllers()` at init (`:18-38`).
- Sets `playerIndex = .index1` and installs an empty `valueChangedHandler` to "claim" the controller (`:55-62`).
- Lightbar through `GCDeviceLight.color`, deduplicated because "hammering this property at 30 Hz appears to cause subsequent writes to be silently coalesced/ignored on macOS 26" (`:174-189`).
- Triggers through `GCDualSenseAdaptiveTrigger.setMode*` (`:237-286`). Only off, feedback, weapon, vibration and slope exist in this API surface as used here; no bow, galloping or machine.
- Rumble through two `CHHapticEngine` instances with `.leftHandle` / `.rightHandle` localities and a 30-second continuous event (`:85-161`).
- Reads back `trigger.mode` / `status` / `armPosition` 250 ms after a change as a diagnostic (`:216-234`).

### 4.3 What works, per its own docs

From `README.md` status table and `CHANGELOG.md` known issues **[docs]**:

| Feature | macOS 13 / 14 | macOS 26, ad-hoc signed |
|---|---|---|
| Connection, battery, sticks, buttons, touchpad | works | works |
| Rumble left | works | works |
| Rumble right | works | partial |
| Lightbar at attach | works | works |
| Lightbar later changes | works | blocked |
| Adaptive triggers | works | blocked |
| Player LEDs / mic LED | works | partial |

- The claimed evidence for "blocked" is that `GCDualSenseAdaptiveTrigger.mode` reads back 0 after `setMode*` on macOS 26.4, despite `GCSupportsControllerUserInteraction`, `GCSupportsGameMode`, `GCSupportedGameControllers`, player index, a value handler, and regular activation policy.
- Its hypotheses: App Store sandbox capability, a private entitlement, or an OS bug. None tested. `SIGNING.md` is an untested procedure, not a result.
- The code comments contradict each other on raw HID: `GameControllerBridge.swift:6-8` says raw HID works for rumble and triggers and only lightbar is filtered; `AppState.swift:161-163` says raw HID is filtered for lightbar, triggers and rumble.

My reading: the GameController-framework result on macOS 26 may be real and is worth knowing if you ever consider that API. The raw-HID conclusion is unsupported, because of defects 1 to 5 above. Whether a correctly formed, non-seized `IOHIDDeviceSetReport` reaches the controller on macOS 26 is still an open question that neither repo answers. **[inferred]**

### 4.4 Connect / disconnect, battery, profiles

- Connect: manager callback hops to main, stores the device, starts input parsing, pushes the profile immediately, then starts the keepalive timer (`App/AppState.swift:113-139`).
- Disconnect: clears the device and stops the timer (`:141-146`). GC-side caches are not cleared, which is what the one open PR fixes.
- Slider drags are coalesced with a cancellable 33 ms `DispatchWorkItem` (`:148-158`).
- Battery: `level * 10` capped at 100, charging if nibble is 1 or 2, read from byte 53 of the USB report; headphones from byte 54 bit 0 (`HID/InputReport.swift:82-90`).
- Profiles: there is exactly one. `Profile` (`Persistence/Profile.swift`) is saved on every mutation to `~/Library/Application Support/DualSenseMac/profile.json` with an atomic write (`Persistence/ProfileStore.swift`). No list, no switching, no per-game binding, despite "profiles" in the repo description. Transient rumble state is stored in the profile too, so a test rumble writes the file twice.

### 4.5 Entitlements, sandbox, Info.plist

- No `.entitlements` file exists. Not sandboxed, no hardened-runtime settings. `CODE_SIGN_IDENTITY = "-"` (ad-hoc), automatic style (`project.yml`). **[code]**
- `Resources/Info.plist` keys: `LSUIElement = true`, `GCSupportsControllerUserInteraction = true`, `GCSupportsGameMode = true`, `GCSupportedGameControllers = [{ProfileName: ExtendedGamepad}]`, `LSMinimumSystemVersion = 13.0`. **[code]**
- No usage-description strings and no Bluetooth or USB entitlements.
- `SIGNING.md:33` says macOS "may prompt for Input Monitoring or controller permissions" on first run. That is the only mention of Input Monitoring in either repo, and it is hedged. **[docs]**
- The app starts as `.accessory` and switches to `.regular` when the settings window opens (`App/DualSenseMacApp.swift:9`, `UI/MenuBarRootView.swift:106`).
- For your app: a sandboxed build would need `com.apple.security.device.usb` and `com.apple.security.device.bluetooth` for raw HID. Gamepad-usage devices are not normally gated by Input Monitoring the way keyboards are, but confirm on macOS 26 by checking `IOHIDManagerOpen`'s return value and `IOHIDCheckAccess`. **[inferred, not from either repo]**

### 4.6 UI ideas worth borrowing

- Menu bar popover as the primary surface: connection glyph, transport and battery line, a few one-tap presets, a test-rumble button, and "Open Settings" (`UI/MenuBarRootView.swift`).
- Feature tabs: Lightbar, Triggers, Motors, LEDs, Input Tester (`UI/SettingsWindow.swift`). For a telemetry-driven app a sidebar (`NavigationSplitView`) with Live / Effects / Controller / Diagnostics would fit better than a flat `TabView`. **[inferred]**
- Side-by-side L2 / R2 editor cards, each with an effect picker and a parameter list that changes with the effect, driven by an enum with associated values (`UI/TriggersTab.swift:32-124`). The clamping that keeps end > start while dragging is a nice touch (`:81-90`).
- Input tester: stick dot-in-circle, trigger progress bars, button chips that light when pressed (`UI/InputTesterTab.swift`). Useful as a diagnostics page to prove the HID link is alive without the game running.
- `defer_` helper that pushes binding setters to the next main-loop tick to avoid "Publishing changes from within view updates" (`UI/LEDsTab.swift:3-10`). With `@Observable` on macOS 26 you likely will not need it.
- Deferred readback logging as a self-check pattern.

### 4.7 Unreliable or stubbed

- Raw HID output path: defects 1 to 5 in section 4.2.
- Bluetooth: detected, but neither output nor input parsing supports it.
- "Profiles": single struct, no management.
- `AppDelegate.openSettings` and its `state` property are never wired up; `state` is never assigned (`App/DualSenseMacApp.swift:4-36`). Dead code beside the `WindowGroup`.
- `LightbarEffect.swift` holds only a static colour type; there are no effects.
- CI builds on `macos-14` only; nothing is tested.
- Built in two days and untouched since.

---

## 5. GitHub issues

Queried through the public REST API on 2026-11-22 (`gh` was not needed).

- `alfaoz/dualsensectl-macos`: 0 issues, 0 PRs, any state.
- `cestercian/ps5-mac-companion`: 0 issues. One open PR, #1 "Fix lightbar not re-applying after Bluetooth reconnect" (opened 2026-08-07 by `whyperyawn`, unmerged, only an automated review bot replied). It clears the GC bridge's cached lightbar / trigger / rumble values on disconnect so they are re-sent on reconnect.

Nothing in either tracker about macOS 15 or 26, Bluetooth trigger output, or Steam Input. The one useful signal from the PR: the controller reverts to defaults on BT reconnect, so any dedup cache must be invalidated on disconnect and full state re-sent on connect.

I did not check the upstream `nowrep/dualsensectl` tracker; it is Linux-focused.

---

## 6. Gotchas for your implementation

Collected from both repos; the label says how solid each is.

1. **Put the report ID in byte 0 of the buffer** passed to `IOHIDDeviceSetReport`, and also pass it as the `reportID` argument. Lengths 63 (USB) and 78 (BT). **[inferred from hidapi; ps5-mac-companion omitting it is the likely cause of its failures]**
2. **Non-seized output is unproven.** dualsensectl-macos works with a seized handle on macOS 15. ps5-mac-companion is non-seized but malformed. Make a correct, non-seized trigger write on macOS 26 over USB and over BT your first spike. **[inferred]**
3. **Something may overwrite your state.** ps5-mac-companion added a 30 Hz re-assert because of "system overrides". If the game, Steam, or the system GameController daemon also writes output reports, last writer wins per field. Set only the valid flags for fields you own, and re-send on a modest timer or on change. **[docs + inferred]**
4. **macOS 26 may ignore GameController.framework trigger and lightbar setters** for ad-hoc signed apps. Do not plan on that API as a fallback. **[docs]**
5. **BT may deliver the short `0x01` report** until calibration feature report `0x05` is read. Request it on connect. **[code for the symptom at `main.c:514-518`; inferred for the fix]**
6. **Input buffer framing is disputed** between the two repos (ID present vs stripped). Branch on the callback's `reportID` and the length. **[code, both]**
7. **USB serial may be absent**; do not key device identity on it. Use `kIOHIDLocationIDKey` or the IOKit registry entry ID. **[code comment for the symptom; inferred for the alternative]**
8. **Re-send full state on BT reconnect** and clear any dedup cache on disconnect. **[PR #1]**
9. **Match with `NSNumber` values** in the Swift matching dictionary. **[code comment]**
10. **Enumerate already-attached devices carefully**; the matching callback normally fires for them once the manager is opened and scheduled, so an extra `IOHIDManagerCopyDevices` pass needs deduplication. **[inferred]**
11. **Rumble needs flags neither project demonstrates correctly.** Use `hid-playstation`: `valid_flag0` bits 0 and 1, or `valid_flag2` bit 2 on newer firmware. **[inferred]**
12. **Bitfield byte order for the BT header:** sequence is the high nibble of byte 1, tag `0x10` is byte 2. **[code, `main.c:221-225`, `:308-316`]**

---

## 7. Recommendation

Write an independent Swift implementation. Do not copy code from dualsensectl-macos. Borrow ideas, and at most small snippets, from ps5-mac-companion.

Reasoning:

- **dualsensectl-macos is GPL.** Copying from it forces GPL-3.0 on your app and makes it impossible to also include anything PolyForm-NC. It would also remove your freedom to pick a permissive licence. The code you would want is about 250 lines of flag constants and bit packing, which are protocol facts you can re-express in Swift from section 3 of this document without copying.
- **There is nothing macOS-specific worth taking from it.** All real I/O is delegated to hidapi, which seizes the device, the opposite of what you need. Its own IOKit code is a plain hotplug monitor.
- **ps5-mac-companion is MIT, so copying is legally easy,** but its HID layer is wrong in several ways and its Bluetooth support is absent. The reusable parts are the UI patterns in section 4.6 and the lifecycle shape of `AppState`. If you lift any file or substantial block, keep "Copyright (c) 2026 Cestercian" and the MIT permission notice in a notices file.
- **For rumble and anything else not covered,** use the Linux `hid-playstation` driver as a factual reference for layout, again without copying code (it is GPL-2.0-or-later).
- **Licence choice for your project:** if you copy no PolyForm-NC code, you can publish under MIT or Apache-2.0 and credit the behavioural reference in the README. If you do copy PolyForm-NC material, the project has to carry those terms for it and cannot be called open source in the OSI sense. This is my reading, not legal advice.

Suggested first steps:

1. A 100-line spike: IOHIDManager non-seized open, send a correctly framed weapon effect to R2 and a lightbar colour, over USB then BT, on macOS 26. This settles gotcha 2.
2. Repeat with ETS2 running under Steam Input enabled and disabled, to see who overwrites whom (gotcha 3).
3. Unit-test the packers against the worked example in section 3.5 and against vectors you compute from the table.
