# RokuLAN Remote

RokuLAN Remote is a small Windows desktop remote for Roku devices reachable on your local network. It discovers devices with Roku ECP/SSDP and a bounded TCP/8060 fallback scan, then sends local Roku ECP commands.

## Downloads

- **`RokuLANRemote.exe`** — portable single-file Windows x64 app.
- **`RokuLANRemote-Package-0.2.0.exe`** — per-user installer/update/repair/uninstall package.
- **`RokuLANRemote-0.2.0-portable.zip`** — portable release archive.
- **`RokuLANRemote-0.2.0-source.zip`** — source/build archive.

The packaged executable is self-contained as a single file but uses the Windows PowerShell 5.1 runtime that ships with Windows 10/11. No Python, Node.js, .NET SDK, or separate script files are required at runtime.

## Features

- SSDP discovery for `roku:ecp`
- bounded local subnet scan for TCP port 8060 as a fallback
- multiple Roku device selection
- manual IP/host connection
- Home, Back, Info, D-pad, OK, replay, rewind, play/pause, fast-forward
- volume buttons when the Roku reports audio-volume support
- Find Remote when the Roku reports support
- text entry using Roku `Lit_` keypresses
- keyboard shortcuts: arrows, Enter, Escape, Space, H, I
- LAN-only operation; no cloud service or telemetry

## Roku setting

Recent Roku OS versions may block keypress commands while **Control by mobile apps / Network access** is set to Limited. If the app discovers your Roku but remote buttons return HTTP 403, change Roku network access to **Enabled** or **Permissive**.

## Installer / package manager

`RokuLANRemote-Package-0.2.0.exe` installs per-user into:

```text
%LOCALAPPDATA%\Programs\RokuLAN Remote
```

It does not require administrator rights. The package UI supports:

- Install / reinstall
- Update by running a newer package over the existing installation
- Repair
- Uninstall
- optional desktop shortcut
- Start-menu shortcut
- Apps & Features registration under the current user

Command-line modes are also recognized:

```text
RokuLANRemote-Package-0.2.0.exe /install
RokuLANRemote-Package-0.2.0.exe /update
RokuLANRemote-Package-0.2.0.exe /repair
RokuLANRemote-Package-0.2.0.exe /uninstall
```

Add `/quiet` to suppress the package UI/dialogs.

## Portable use

Run `RokuLANRemote.exe`. Discovery starts automatically shortly after the window appears. You can also enter a Roku IP address manually, for example:

```text
192.168.0.239
```

## Build layout

```text
src/RokuLanRemote.ps1              application source
installer/Installer.ps1            package-manager source template
build/make_winexec_pe.py            tiny deterministic PE launcher builder
build/build_release.py              release builder
dist/                               generated release files
```

The release builder creates a tiny Windows x64 GUI launcher and appends the readable PowerShell source as its payload. At runtime the launcher writes that payload to a temporary script, runs it with the built-in Windows PowerShell runtime, and removes the temporary file when the UI closes. The package executable embeds both the portable app and its installer logic, and verifies the embedded app with SHA-256 before installation. The format is intentionally simple and inspectable.

Build from a Python 3 environment:

```text
python build/build_release.py
```

No third-party Python packages are required.

## Security / trust

The downloadable executables in this development build are **unsigned**. Windows SmartScreen or antivirus software may warn about a newly created unsigned executable, especially before the project has reputation. For a public release, sign the release artifacts with an Authenticode code-signing certificate and publish SHA-256 hashes alongside each release.

The application does not request elevation and installs only for the current Windows user.

## Roku / ECP note

Roku ECP is Roku's local-network control interface. Review Roku's current ECP terms and platform requirements before publicly distributing a third-party remote application. Roku and related marks are trademarks of Roku, Inc.; this project is not affiliated with or endorsed by Roku, Inc.

## License

MIT. See `LICENSE`.
