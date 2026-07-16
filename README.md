<div align="center">

<img src="Sources/ScarlettApp/Resources/AppIcon.png" alt="App icon" width="160" height="160" />

<h1>Scarlett MixControl</h1>
<h3>Community Edition</h3>

A native macOS replacement for Focusrite's discontinued <strong>MixControl 1.10.6</strong>,<br/>
for the <strong>1st-generation Scarlett 8i6</strong>.

<br/>

<a href="https://github.com/MarecekW/scarlett-mixcontrol-1stgen/releases/latest">
  <img alt="Download latest" src="https://img.shields.io/github/v/release/MarecekW/scarlett-mixcontrol-1stgen?style=for-the-badge&label=Download&color=2563eb" />
</a>
&nbsp;
<img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1d4ed8?style=for-the-badge&logo=apple&logoColor=white" />
&nbsp;
<img alt="License MIT" src="https://img.shields.io/badge/License-MIT-3aa55d?style=for-the-badge" />

<br/>
<br/>

</div>

> [!NOTE]
> Focusrite discontinued MixControl years ago. On modern macOS the app still launches but no longer finds the device — so the matrix mixer, routing, and DSP features your hardware actually has are unreachable. If you own a 1st-gen Scarlett 8i6 and want to use those features again on a modern Mac, this is for you.

<br/>

<div align="center">
  <img src="docs/screenshots/scr-mixcontrol-mixer.png" alt="Mixer tab — 18×6 matrix mixer with live peak meters" width="80%" />
</div>

<br/>

## ✨ Features

|     |                                                                                             |
| --- | ------------------------------------------------------------------------------------------- |
| 🎛️  | **Full 18 × 6 matrix mixer** with per-cell gain, mute, solo, pan, stereo link               |
| 🔀  | **Output routing** — Monitor / Phones / S/PDIF can pick any source (DAW, Analog, Mix M1–M6) |
| 🎤  | **USB capture routing** — choose what your DAW sees on each input channel                   |
| 📌  | **Pinned DAW return strip** — DAW 1/2 back into the matrix with one linked fader            |
| 🔘  | **Hardware switches** — line/inst impedance, hi/lo gain, clock source, sample rate          |
| 📊  | **Live peak meters** — all 18 inputs + 6 mix buses + 6 DAW playbacks, with held peaks       |
| 💾  | **Save to hardware** — persist mixer state to device flash, survives power cycle            |
| 📁  | **Snapshots** — save / load full configurations as `.8i6` JSON files (⌘S / ⌘O)              |
| 🔌  | **Connection resilience** — auto-reconnect on USB drops, clear status overlay               |

<br/>

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="docs/screenshots/scr-mixcontrol-routing.png" alt="Routing tab" width="100%" /><br/>
        <sub><strong>Routing</strong> — physical outputs + USB capture</sub>
      </td>
      <td align="center">
        <img src="docs/screenshots/scr-mixcontrol-presets.png" alt="Presets tab" width="100%" /><br/>
        <sub><strong>Presets</strong> — save / load full configurations</sub>
      </td>
      <td align="center">
        <img src="docs/screenshots/scr-mixcontrol-device.png" alt="Device tab" width="100%" /><br/>
        <sub><strong>Device</strong> — hardware info, clock, event log</sub>
      </td>
    </tr>
  </table>
</div>

<br/>

## 📦 Installation

### Download a release _(recommended)_

1. Grab `Scarlett.MixControl.app.zip` from the [**latest release**](https://github.com/MarecekW/scarlett-mixcontrol-1stgen/releases/latest).
2. Unzip and drag `Scarlett MixControl.app` to `/Applications`.
3. **First launch only** — macOS Gatekeeper will block the app (we use ad-hoc codesigning, not a paid Developer ID). One of these will get past it:
   - **Right-click** the app → **Open** → confirm the warning dialog.
   - Or in Terminal: `xattr -dr com.apple.quarantine "/Applications/Scarlett MixControl.app"`

### Build from source

Requires the Xcode 15 / Swift 5.9+ toolchain.

```sh
git clone https://github.com/MarecekW/scarlett-mixcontrol-1stgen.git
cd scarlett-mixcontrol-1stgen
./scripts/make-app.sh
open "build/Scarlett MixControl.app"
```

For dev iteration without packaging: `swift run scarlett-app`. There's also a `scarlett-cli` companion for low-level protocol poking — try `swift run scarlett-cli --help`.

<br/>

## 🎯 Compatibility

| Device                       | Status                                               |
| ---------------------------- | ---------------------------------------------------- |
| **Scarlett 8i6** _(1st gen)_ | ✅ &nbsp; Officially supported — tested on macOS 14+ |
| Scarlett 6i6 _(1st gen)_     | 🟡 &nbsp; Detected, support pending                  |
| Scarlett 16i8 _(1st gen)_    | 🟡 &nbsp; Detected, support pending                  |
| Scarlett 18i6 _(1st gen)_    | 🟡 &nbsp; Detected, support pending                  |
| Scarlett 18i8 _(1st gen)_    | 🧪 &nbsp; Experimental                               |
| Scarlett 18i20 _(1st gen)_   | 🟡 &nbsp; Detected, support pending                  |
| Scarlett 2nd / 3rd / 4th gen | ❌ &nbsp; Different protocol — won't work            |
| Saffire (FireWire) family    | ❌ &nbsp; Different transport — won't work           |

> 🧪 18i8 has _experimental_ support — the matrix mixer, routing, and most DSP controls work, but hasn't been battle-tested the way 8i6 has. Other 1st-gen Scarletts (6i6, 16i8, 18i6, 18i20) still show a friendly "not yet supported" screen.

<br/>

## 🛠️ How it works

<details>
<summary><strong>Tech tour (click to expand)</strong></summary>

<br/>

The 1st-gen Scarletts are **USB Audio Class 2.0** devices. macOS's built-in `usbaudiod` claims the audio + MIDI streaming interfaces, but doesn't touch the **audio control interface** (endpoint 0). That's how this app coexists with normal audio playback — every mixer / routing / metering command is a `IOUSBDeviceInterface.DeviceRequest` to endpoint 0, sent through the same USB stack `usbaudiod` is using, without ever issuing `USBDeviceOpen` (which would fail with `kIOReturnExclusiveAccess`).

The protocol itself was reverse-engineered by extracting the per-product signal tables (`_USB14Tracker_IpSigTab`, `_USB14Tracker_OpSigTab`, default routing tables, etc.) directly from the original MixControl 1.10.6 binary, then disassembling key dispatch functions (`MacHWDevice::routeChannel`, `setMonMono`, etc.) to confirm `wValue` / `wIndex` semantics.

**The three routing dimensions:**

| `wIndex` | Purpose                   | UI surface                                 |
| -------- | ------------------------- | ------------------------------------------ |
| `0x3200` | Matrix-mixer input source | Source picker on each matrix channel strip |
| `0x3300` | Physical output routing   | "Output assignments" panel in Routing tab  |
| `0x3400` | USB capture routing       | "USB capture" panel in Routing tab         |

**Firmware quirks worth knowing:**

- Routing GETs always return `00 00` regardless of what was last set — UserDefaults persistence is the only way to remember routes across launches.
- Matrix-source assignment silently fails if the source is already wired to another channel — the app does an explicit `.off` disconnect on the previous owner first.
- The `setMonitorMono` USB command crashes the firmware when sent from our process, even with byte-perfect parity to MixControl. Probably an undocumented authorization handshake at startup we haven't identified — the Mn button is hidden until we crack it.

For full deep-dive, read the commit history — `d175367` (the matrix-mixer breakthrough) and `1294ff7` (feature parity additions) cover most of the protocol reasoning.

</details>

<br/>

## 🤝 Contributing

The biggest open item is **support for the other 1st-gen Scarletts** — 6i6, 16i8, 18i6, 18i8, 18i20. The infrastructure is in place (`DeviceProfile` system, USB PID detection), but each device needs:

1. **Its byte tables extracted** from MixControl's binary (or transcribed from `Sources/ScarlettCore/DeviceProfile.swift` — drafts for 18i6 and 18i8 are already there from disassembly).
2. **Validation against real hardware** — without testing, every port is theoretical.
3. **UI dimensions wired up** — array sizing in `MixerState` (currently hardcoded for 6 mix buses) and channel/output counts in views need to derive from the connected device's profile.

If you have one of these devices and want to help, [open an issue](https://github.com/MarecekW/scarlett-mixcontrol-1stgen/issues/new) or send a PR.

<br/>

## 🙏 Credits

Standing on shoulders:

- [**@x42** (Robin Gareus)](https://github.com/x42) — original Python reverse-engineering of the Scarlett 18i6 protocol in [`scarlettmixer`](https://github.com/x42/scarlettmixer). Many `wValue` / `wIndex` constants were first documented in his code.
- **Linux kernel** — `sound/usb/mixer_scarlett.c` was an essential cross-reference, even where its 8i6 byte tables turned out to be marked _"untested..."_ (and indeed wrong about S/PDIF and Mix bus bytes).
- [**@geoffreybennett** (Geoffrey Bennett)](https://github.com/geoffreybennett) — author of [`alsa-scarlett-gui`](https://github.com/geoffreybennett/alsa-scarlett-gui), the most thorough open-source Scarlett control panel for Linux.
- **Focusrite** — for shipping a control panel binary on their support site that didn't strip its data tables.

<br/>

## 📜 License

Released under the [MIT](LICENSE) license.

This is an independent community project. It is not affiliated with, endorsed by, or supported by Focusrite Audio Engineering Ltd. "Scarlett", "MixControl", and "Focusrite" are trademarks of their respective owners.

<br/>

<div align="center">
<sub>Built by <a href="https://github.com/MarecekW">@MarecekW</a> · co-authored with Claude</sub>
</div>
