# Security

RokuLAN Remote is designed to communicate only with Roku ECP endpoints on the local network.

Please report security issues privately to the maintainer rather than opening a public issue containing exploit details.

Release guidance:

- sign public Windows binaries with Authenticode;
- publish SHA-256 hashes with releases;
- keep update packages immutable once published;
- do not add telemetry or remote code download without explicit documentation and user consent;
- treat device names and local IP addresses as local/private data.
