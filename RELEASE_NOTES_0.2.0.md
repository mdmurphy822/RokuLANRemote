# RokuLAN Remote v0.2.0

First packaged open-source release of RokuLAN Remote for Windows.

## Highlights

- Local-network Roku remote using Roku ECP on TCP port 8060.
- Automatic discovery via SSDP with a bounded TCP/8060 subnet-scan fallback.
- Multiple-device selection and manual IP/host connection.
- Home, Back, Info, D-pad, OK, replay, rewind, play/pause, fast-forward, text entry, and keyboard shortcuts.
- Conditional volume and Find Remote controls when reported by the Roku device.
- Portable single-file Windows x64 executable.
- Per-user installer with install/update/reinstall, repair, uninstall, Start-menu integration, optional desktop shortcut, and Apps & Features registration.
- SHA-256 verification of the embedded application payload.
- No telemetry, cloud service, account, or elevation requirement.

## Windows downloads

- `RokuLANRemote.exe` — portable Windows x64 application.
- `RokuLANRemote-Package-0.2.0.exe` — installer/update/repair/uninstall package.
- `RokuLANRemote-0.2.0-portable.zip` — portable archive.
- `RokuLANRemote-0.2.0-release.zip` — bundled release package.
- `RokuLANRemote-0.2.0-source.zip` — source archive.
- `SHA256SUMS.txt` — hashes for the executable artifacts.

## Roku network-access setting

If discovery succeeds but keypresses return HTTP 403, set **Settings → System → Advanced system settings → Control by mobile apps → Network access** to **Enabled** or **Permissive** on the Roku.

## Trust note

The v0.2.0 Windows binaries are unsigned. Windows SmartScreen or antivirus products may warn about newly published unsigned executables. Verify downloads with `SHA256SUMS.txt`.

RokuLAN Remote is not affiliated with or endorsed by Roku, Inc.
