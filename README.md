<div align="center">

# RokuLAN Remote

### A simple Windows remote for Roku devices on your home network.

[![Release](https://img.shields.io/github/v/release/mdmurphy822/RokuLANRemote?label=release)](https://github.com/mdmurphy822/RokuLANRemote/releases/latest)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Local Network](https://img.shields.io/badge/Control-Local%20Network-success)](#privacy)

**No account. No cloud service. No subscription.**  
RokuLAN Remote finds Roku devices on your LAN and turns your Windows PC into a desktop remote.

[Download the latest release](https://github.com/mdmurphy822/RokuLANRemote/releases/latest) · [Report an issue](https://github.com/mdmurphy822/RokuLANRemote/issues) · [View source](https://github.com/mdmurphy822/RokuLANRemote)

</div>

---

## What it does

RokuLAN Remote controls compatible Roku devices directly over your local network using Roku's External Control Protocol (ECP).

It automatically searches your network for Roku devices, lets you choose one, and provides a familiar desktop remote with navigation, playback, text entry, volume controls, and keyboard shortcuts.

### Highlights

- **Automatic Roku discovery** using SSDP, with a TCP port `8060` subnet-scan fallback
- **Multiple Roku support** with a device selector
- **Manual IP connection** when you already know the Roku address
- **Full navigation controls** — Home, Back, Info, D-pad, and OK
- **Playback controls** — Replay, Rewind, Play/Pause, and Fast Forward
- **Text entry** from your PC keyboard
- **Volume controls** when supported by the connected Roku device
- **Find Remote** when the connected Roku reports support
- **Keyboard shortcuts** for fast control without clicking
- **Local-only operation** with no account, telemetry, or cloud dependency

---

## Download

Go to the **[latest GitHub release](https://github.com/mdmurphy822/RokuLANRemote/releases/latest)** and choose the package that fits how you want to use the app.

| Download | Best for |
|---|---|
| **`RokuLANRemote-Package-0.2.0.exe`** | Recommended. Installs RokuLAN Remote with Start-menu integration and uninstall support. |
| **`RokuLANRemote.exe`** | Portable use. Download and run without installing. |
| **`RokuLANRemote-0.2.0-portable.zip`** | Portable app in a ZIP archive. |
| **`RokuLANRemote-0.2.0-release.zip`** | Complete release bundle. |
| **`RokuLANRemote-0.2.0-source.zip`** | Source/build archive. |
| **`SHA256SUMS.txt`** | SHA-256 checksums for release verification. |

### Requirements

- Windows 10 or Windows 11
- A Roku device connected to the same reachable home network as the PC
- Roku **Control by mobile apps / Network access** set to **Enabled** or **Permissive**

RokuLAN Remote uses the Windows PowerShell 5.1 runtime included with Windows. You do not need to install Python, Node.js, the .NET SDK, or any separate runtime to use the packaged app.

---

## Quick start

### Installed version

1. Download **`RokuLANRemote-Package-0.2.0.exe`** from the latest release.
2. Run the package and choose **Install**.
3. Open **RokuLAN Remote** from the Start menu.
4. Wait a moment while the app discovers Roku devices on your network.
5. Select your Roku and start controlling it.

### Portable version

1. Download **`RokuLANRemote.exe`**.
2. Run it.
3. Select a discovered Roku device.

If discovery does not find your Roku, enter its IP address manually in the app. A typical home-network address looks like:

```text
192.168.0.239
```

---

## Roku network setting

If RokuLAN Remote can see your Roku but button presses do not work, check the Roku's network-control setting.

On the Roku, open:

**Settings → System → Advanced system settings → Control by mobile apps → Network access**

Choose **Enabled** or **Permissive**.

When Roku is set to **Limited**, it may answer discovery requests while rejecting remote-control keypress commands with HTTP `403 Forbidden`.

---

## Controls

### Remote buttons

RokuLAN Remote provides controls for:

- Home
- Back
- Info
- Up / Down / Left / Right
- OK / Select
- Instant Replay
- Rewind
- Play / Pause
- Fast Forward
- Volume Up / Down / Mute when supported
- Find Remote when supported
- Text entry

### Keyboard shortcuts

| Key | Roku action |
|---|---|
| `↑` `↓` `←` `→` | Navigate |
| `Enter` | OK / Select |
| `Esc` | Back |
| `Space` | Play / Pause |
| `H` | Home |
| `I` | Info |

---

## Installer, update, repair, and uninstall

The installer package installs RokuLAN Remote for the current Windows user at:

```text
%LOCALAPPDATA%\Programs\RokuLAN Remote
```

It does **not** require administrator rights.

The package supports:

- Install or reinstall
- Update by running a newer package
- Repair
- Uninstall
- Start-menu shortcut
- Optional desktop shortcut
- Windows Apps & Features registration

### Command-line package options

```text
RokuLANRemote-Package-0.2.0.exe /install
RokuLANRemote-Package-0.2.0.exe /update
RokuLANRemote-Package-0.2.0.exe /repair
RokuLANRemote-Package-0.2.0.exe /uninstall
```

Add `/quiet` for unattended operation.

---

## Privacy

RokuLAN Remote is designed to operate entirely on your local network.

- No RokuLAN Remote account
- No telemetry
- No analytics
- No cloud control service
- No remote server required

The app communicates directly with Roku devices reachable from your PC over the local network.

---

## Troubleshooting

### Roku is not discovered

Make sure the PC and Roku can communicate across your home network. Guest Wi-Fi, client isolation, or separate VLANs may block device-to-device traffic even when both networks use the same router.

You can also connect by entering the Roku's IP address manually.

### Roku is discovered, but buttons do nothing

Check **Control by mobile apps → Network access** on the Roku and set it to **Enabled** or **Permissive**.

### I know the Roku IP and want to test it manually

Roku ECP normally listens on TCP port `8060`. From PowerShell:

```powershell
curl.exe "http://192.168.0.239:8060/query/device-info"
```

A working Roku should return device information as XML.

### Windows shows a security prompt

Windows may display SmartScreen or antivirus prompts for newly downloaded executables. Release checksums are published in `SHA256SUMS.txt` so downloads can be verified against the release assets.

---

## For developers and contributors

RokuLAN Remote is intentionally small and inspectable.

```text
src/RokuLanRemote.ps1              Windows GUI and Roku ECP logic
installer/Installer.ps1            installer/package-manager source
build/make_winexec_pe.py            Windows launcher builder
build/build_release.py              release builder
.github/workflows/                  GitHub release automation
```

### Build from source

Python 3 is required only for building release artifacts:

```text
python build/build_release.py
```

No third-party Python packages are required by the release builder.

Contributions, bug reports, and improvements are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md).

---

## How it works

RokuLAN Remote communicates with Roku devices through Roku's LAN-based External Control Protocol.

Discovery uses SSDP for `roku:ecp`. If multicast discovery does not return a device, the app can perform a bounded scan of the local IPv4 subnet for devices responding on TCP port `8060`. Once connected, remote actions are sent directly to the selected Roku over HTTP.

---

## License

RokuLAN Remote is open source under the **[MIT License](LICENSE)**.

Roku and related marks are trademarks of Roku, Inc. RokuLAN Remote is an independent open-source project and is not affiliated with or endorsed by Roku, Inc.
