# Changelog

## 0.2.0

- Added portable single-file Windows x64 `RokuLANRemote.exe`.
- Added downloadable per-user package manager executable.
- Added install, update/reinstall, repair, uninstall, Start-menu shortcut, optional desktop shortcut, and Apps & Features registration.
- Added package payload SHA-256 verification.
- Preserved SSDP + TCP/8060 discovery and manual-IP fallback.
- Carried forward the 0.1.1 bounded synchronous LAN HTTP fix that prevents WinForms verification hangs.

## 0.1.1

- Replaced blocking sync-over-async `HttpClient` calls with bounded synchronous LAN requests.
- Added explicit proxy bypass and connect/read timeouts.

## 0.1.0

- Initial PowerShell/WinForms proof of concept.
