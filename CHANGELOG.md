# Changelog

All notable changes to PSWinOps are documented in this file. Versions follow
[Semantic Versioning](https://semver.org/). Dates are UTC.

> **Note on history**: only `0.0.1` through `0.0.23` were ever published to the
> PowerShell Gallery. Work merged to `main` after `0.0.23` (2026-05-21) was never
> released as `0.0.24`/`0.1.x`/`0.12.x` — those version numbers never shipped. That
> accumulated work is released here as `1.0.0`.

## [1.1.0] - 2026-09-05

### Added

- Short aliases for all 139 public functions (e.g. `gwu` for `Get-WindowsUpdate`,
  `gaui` for `Get-ADUserInventory`), registered via `AliasesToExport`.

## [1.0.0] - 2026-09-05

First stable release. Consolidates everything merged to `main` since `0.0.23`
(2026-05-21), none of which was previously published to the PowerShell Gallery.

### Added

- **New `eventlog` domain**: `Get-UnexpectedShutdown`, `Get-LogonFailure`,
  `Get-ServiceCrashEvent`, `Get-ProcessCrashEvent`, `Get-DiskErrorEvent`,
  `Get-ScheduledTaskFailure`, `Get-WindowsUpdateFailure`, `Get-SchannelError`
  (#63, #81, #83, #88, #89, #90, #91, #92).
- **New `security` domain**: `Get-AuditPolicy` — advanced audit policy subcategories
  via `auditpol.exe` (#76).
- **New `certificate` domain**: `Get-ExpiringCertificate` — local-store certificates
  expiring within a threshold (#85).
- **`activedirectory`**: `Get-ADLockoutSource` — traces account lockouts to their
  source machine via event 4740 on the PDC Emulator (#87).
- **`system`**: `Get-RebootHistory` (reboot/shutdown reconstruction from event log)
  (#61), `Get-CrashDump` (crash dump inventory) (#75), `Get-DriverInventory`
  (signed-driver inventory) (#84).
- **`network`**: `Reset-NetworkStack` (Winsock/TCP-IP/DNS/ARP reset) (#77),
  `Get-ProcessByPort` (TCP/UDP endpoint-to-process correlation) (#78).
- **`system`**: `Set-EnvironmentVariable` (#79), `Stop-ProcessTree` (#80),
  `Get-ServiceAccount` (service logon account audit) (#82).
- **`windowsupdate`**: `Reset-WindowsUpdateComponent` — resets the Windows Update
  service stack, with `-IncludeNetworkReset` (#62).
- **`utils`**: `ConvertTo-Markdown` — deterministic GitHub-Flavored Markdown table
  export (#100).

### Changed

- Standardized action-function output on a typed `PSWinOps.ActionResult` shape
  (status, target, errors, timestamp) across `Clear-Arp`, `Edit-HostsFile`,
  `Remove-NetworkRoute`, `Set-NTPClient`, `Remove-ProxyConfiguration`,
  `Set-ProxyConfiguration`, `Clear-WindowsUpdateCache` (#108).
- `Remove-UserProfile` now reconciles registry profile entries against actual
  `C:\Users` folders instead of trusting the registry alone (#58).

### Fixed

- Excluded `Integration`-tagged Pester tests from the Gallery publish workflow
  (#106).
- Added missing `PSWinOps.Format.ps1xml` default views for the new Windows Update
  result types (#101).

### Documentation

- Synced the public-function inventories and counts in `about_PSWinOps.help.txt`
  with the current `Public/` tree (#102).
- Completed the `PSTypeName` registry in `about_PSWinOps.help.txt` (#103).
- Synced `CLAUDE.md` domain list and `PSTypeName` registry with the current
  codebase (#109).

## [0.0.23] - 2026-05-21

### Added

- **New `iis` domain**, registered in CI and `about_PSWinOps`:
  - `Set-IISBindingCertificate` — idempotent HTTPS binding certificate rotation,
    `-WhatIf`/`-Confirm` (#47).
  - `Get-IISParsedLog` — typed streaming parser for IIS W3C log files (#49).
  - `Get-IISWorkerProcess` — `w3wp.exe` inventory joined with app pool/site data
    (#50).
  - `Get-IISCurrentRequest` — currently executing HTTP requests (#51).
  - `Watch-IISLog` — real-time IIS log tailer (#52).
  - `Get-IISFailedRequestTrace` — FREB trace file parser (#53).
  - `Get-IISCertificateBinding` — HTTPS binding-to-certificate inventory (#54).
  - `Test-IISBindingCertificate` — six-check binding certificate auditor (#55).
  - `Get-IISAppPoolHistory` — app pool lifecycle reconstruction from event logs
    (#56).

### Changed

- Automated remediation pass: code quality, testability, and monitor-function
  extraction across the module (#48).

## [0.0.22] - 2026-04-11

### Changed

- General improvements across existing functions (#44).

## [0.0.21] - 2026-04-10

### Fixed

- `Set-PageFile`: fixed a "Generic failure" error (#43).

## [0.0.20] - 2026-04-08

### Added

- **New `windowsupdate` domain** with its first functions (#42).
- General improvements across existing functions (#41).

## [0.0.19] - 2026-04-06

### Changed

- `Get-ADPasswordStatus` rewritten with Fine-Grained Password Policy (FGPP)
  support (#40).

### Fixed

- Corrected `.gitattributes` line-ending handling (`eol=crlf` → `text auto`).

## [0.0.18] - 2026-04-04

### Added

- **New `activedirectory` domain**: 9 AD functions with tests and format views
  (#39).

### Fixed

- `Get-ClusterHealth`: PowerShell 7 compatibility (quorum resource resolution,
  `WinPSCompatSession` warning, string normalization) and exclusion of system
  groups from health scoring.
- `Get-DnsServerHealth`: use `127.0.0.1` instead of `localhost` for
  self-resolution; removed `-DnsOnly` from the self-resolution test.
- `Get-CertificateAuthorityHealth`: unknown certificate expiry now reports
  `Degraded` instead of `Healthy`; falls back to the certificate store when
  `certutil` has no expiry data.
- `Get-WSUSHealth`: use a proportional error rate instead of an absolute count.

## [0.0.17] - 2026-04-02

### Added

- **New healthcheck functions**, including `Get-ExchangeServerHealth` (#34), and
  the `PSWinOpsHealthStatus` enum plus the `about_PSWinOps` help topic (#33).

### Changed

- `Invoke-RemoteOrLocal` rewritten (#30).
- `OverallHealth` computation moved into the `process {}` block for health-check
  functions (#31).

### Fixed

- Miscellaneous cleanup: synopsis text, `#Requires` statements, module-scoped
  local names (#32).
- Replaced `Clear-Host` with `Console.SetCursorPosition` in monitor functions to
  eliminate terminal flicker (#35).
- Documentation coherence pass across two audit axes (#36, #37, #38).

## [0.0.16] - 2026-03-31

### Added

- Default `TableControl` format views for all typed outputs (#29).

## [0.0.15] - 2026-03-31

### Added

- New functions with expanded test coverage (#28).

### Fixed

- NTP function fixes (#27).

## [0.0.14] - 2026-03-26

### Fixed

- Miscellaneous fixes (#25).

## [0.0.13] - 2026-03-26

### Changed

- General improvements (#23) and a coherence pass across the module (#24).

## [0.0.12] - 2026-03-23

### Added

- `Get-NetworkStatistic`, `Get-NetworkConnection`.

### Changed

- Optimization pass (#22); expanded Pester test coverage (#20).

## [0.0.11] - 2026-03-22

### Changed

- Repository folder structure renamed to the current `Public/<domain>/` layout
  (#19).

## [0.0.10] - 2026-03-20

### Added

- `Get-ProxyConfiguration` formalized with tests (#16).
- First documentation/coherence audit pass (#18).

### Changed

- General improvements (#17).

## [0.0.9] - 2026-03-20

### Added

- **New `proxy` domain**: `Get-ProxyConfiguration`, `Set-ProxyConfiguration`,
  `Remove-ProxyConfiguration`, `Test-ProxyConnection`.

### Changed

- Optimization pass (#15).

## [0.0.8] - 2026-03-18

### Fixed

- Minor fixes (#14).

## [0.0.7] - 2026-03-18

### Added

- `Get-SystemSummary` (#10), `Get-PendingReboot` (#12).
- `PSTypeName` added to all typed outputs (#13).

### Changed

- General improvements (#11).

## [0.0.6] - 2026-03-16

### Added

- `Get-ComputerUptime` (#9).

### Fixed

- Removed a useless property from session output (#8).

## [0.0.5] - 2026-03-12

### Added

- `Get-NTPPeer`.

## [0.0.4] - 2026-03-12

### Added

- `Get-NTPSyncStatus`, `Sync-NTPTime` (#7).

### Fixed

- Session function fixes (#5, #6).

## [0.0.3] - 2026-03-12

### Fixed

- `Connect-RdpSession` fix.

## [0.0.2] - 2026-03-11

### Added

- CI pipeline (#1).
- `Get-RandomPassword`.
- `ConvertFrom-MisencodedString` (#2).
- **New `sessions` domain** (now `rdp`): `Get-RdpSession`, `Connect-RdpSession`,
  `Disconnect-RdpSession`, `Remove-RdpSession`, `Get-RdpSessionHistory` (#3, #4).

## [0.0.1] - 2026-02-26

### Added

- Initial release: module scaffolding, manifest, and the first `ntp` functions
  (`Get-NTPConfiguration`, `Set-NTPClient`).
