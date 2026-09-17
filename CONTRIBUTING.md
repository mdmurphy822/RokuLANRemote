# Contributing

Thanks for considering a contribution to RokuLAN Remote.

## Development principles

- Keep the core Windows build dependency-light.
- Keep all Roku control traffic local to the user's network.
- Do not add telemetry by default.
- Prefer documented Roku ECP behavior.
- Gracefully handle HTTP errors such as `403 Forbidden`.
- Discovery must verify that port `8060` is actually a Roku ECP endpoint before presenting it as a Roku.
- Keep keyboard and mouse operation accessible.

## Testing checklist

Before opening a pull request, test at least:

1. SSDP discovery on a normal home LAN.
2. Manual-IP connection.
3. A device with `Control by mobile apps` enabled/permissive.
4. A device in Limited mode and confirm the app reports the `403` clearly.
5. D-pad, Home, Back, Select, and Play/Pause.
6. Text entry on a Roku screen that exposes an on-screen keyboard.
7. More than one discovered Roku if available.

## Style

The main implementation targets Windows PowerShell 5.1 for broad Windows compatibility. Avoid syntax that requires PowerShell 7 unless the minimum version is intentionally changed.
