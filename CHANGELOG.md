# Changelog

## [Unreleased]

### Fixed

- Synchronized the documented public-function inventories and counts in `about_PSWinOps.help.txt`.
- Completed the `PSTypeName` registry in `about_PSWinOps.help.txt` and corrected its count to 119.
- Added default format views for Windows Update result objects.
- Excluded `Integration`-tagged tests from the release publication workflow.

## 0.12.0 - 2026-09-04 UTC
### Added
- ConvertTo-Markdown: Convert PowerShell objects to deterministic GitHub-Flavored Markdown tables with stable column and row ordering
- Get-ADLockoutSource: Trace the source machine of an AD account lockout via event 4740 on the PDC Emulator
- Get-DiskErrorEvent: Classify and aggregate Disk, Ntfs, storahci, and storport storage errors from the System log
- Get-ProcessCrashEvent: Correlate Application Error, Windows Error Reporting, and optional Application Hang events with per-process counts
- Get-SchannelError: Normalize Schannel TLS, certificate, and negotiation failures from the System log
- Get-ScheduledTaskFailure: Report Task Scheduler task-start and action failures with XML field extraction and per-task counts
- Get-WindowsUpdateFailure: Report Windows Update failures, restart requirements, and optional successful installations from the System log

## 0.11.0 - 2026-09-04 UTC
### Added
- Get-ExpiringCertificate: Find local-store certificates expiring within a threshold of days

## 0.10.0 - 2026-08-11 UTC
### Added
- Get-DriverInventory: Structured signed-driver inventory via Win32_PnPSignedDriver, filterable by class or unsigned-only, local or remote

## 0.9.1 - 2026-07-06 UTC
### Added
- Get-ServiceCrashEvent: Aggregate Service Control Manager crash events per service with counts and exit codes

## 0.9.0 - 2026-07-06 UTC
### Added
- Get-ServiceAccount: Audit service logon accounts across local or remote computers

## 0.8.0 - 2026-07-06 UTC
### Added
- Get-LogonFailure: Aggregate and decode Windows Security 4625 failed-logon events

## 0.7.0 - 2026-07-06 UTC
### Added
- Stop-ProcessTree: Terminate a process and its entire descendant tree, leaves first

## 0.6.0 - 2026-07-06 UTC
### Added
- Set-EnvironmentVariable: Sets or deletes a Machine- or User-scoped environment variable on local or remote computers

## 0.5.0 - 2026-07-06 UTC
### Added
- Get-ProcessByPort: Correlate TCP/UDP endpoints with their owning process details

## 0.4.0 - 2026-07-06 UTC
### Added
- Reset-NetworkStack: Reset the Windows network stack (winsock, TCP/IP, DNS cache, ARP)

## 0.3.0 - 2026-07-05 UTC
### Added
- Get-AuditPolicy: Report advanced audit policy subcategory settings from auditpol.exe

## 0.2.1 - 2026-07-05 UTC
### Added
- Get-CrashDump: Inventory Windows crash memory dumps with size, type and BugCheck code

## 0.2.0 - 2026-07-05 UTC
### Added
- Get-UnexpectedShutdown: Reports shutdown and restart events with cause, expectedness and initiator

## 0.1.0 - 2026-06-24
### Added
- feat(windowsupdate): add Reset-WindowsUpdateComponent — resets the Windows Update service stack to a clean state (stop BITS/wuauserv/appidsvc/cryptsvc, delete qmgr*.dat, back up SoftwareDistribution & Catroot2, reset BITS/wuauserv SDDL, reregister Windows Update DLLs, restart services, trigger detection with usoclient fallback); optional -IncludeNetworkReset resets Winsock/WinHTTP (requires reboot, may drop remote sessions); SupportsShouldProcess (ConfirmImpact=High), Test-IsAdministrator guard, remote execution via Invoke-RemoteOrLocal; returns PSWinOps.WindowsUpdateResetResult.

## 0.0.24 - 2026-06-24
### Added
- feat(system): add Get-RebootHistory — correlates Windows System event log entries (1074, 1076, 6005, 6006, 6008, Kernel-Power 41) to reconstruct reboot/shutdown history per computer; classifies each event as Planned/Unexpected/Crash/PowerLoss/Unknown with DowntimeMinutes, Cause, Initiator, Comment; -MaxEvents, -After, -Before filters; remote execution via Invoke-RemoteOrLocal (#59).

## 0.0.23 - 2026-05-21
### Added
- feat(iis): introduce new public domain Public/iis/ (registered in CI matrix and about_PSWinOps).
- feat(iis): add Set-IISBindingCertificate — replace SSL/TLS certificate on IIS HTTPS bindings with idempotent rotation, -WhatIf/-Confirm (ConfirmImpact=High), remote execution via WinRM, pipeline-by-property-name from Get-SSLCertificate / Get-IISHealth (#47).
- feat(iis): add Get-IISParsedLog — stream-parse IIS W3C log files into typed PSWinOps.IISLogEntry objects; header re-detection, dash-normalisation, UserAgent "+"-to-space decoding; -After/-Before window, -Method/-Status/-ClientIP multi-value OR filters, -UriLike wildcard, -Tail circular buffer, pipeline-by-property-name FullName (#49).
- feat(iis): add Get-IISWorkerProcess — inventory IIS w3wp.exe processes joined with AppPoolName, Sites/Applications, identity, PID, uptime, CPU, working/private/virtual memory, thread/handle counts; WebAdministration → IISAdministration → appcmd/CIM fallback; -AppPoolName/-ProcessId filters; Status enum (Running/Orphaned/Failed/IISNotInstalled/NoWorkerProcess) (#50).
- feat(iis): add Get-IISCurrentRequest — list HTTP requests currently executing in IIS (typed equivalent of `appcmd list requests`) with ComputerName, ProcessId, AppPoolName, SiteName, Url, Verb, ClientIPAddress, TimeElapsed/TimeElapsedMs, PipelineState; -AppPoolName/-SiteName wildcards and -MinElapsedMs threshold (#51).
- feat(iis): add Watch-IISLog — real-time IIS W3C log tailer emitting typed PSWinOps.IISLogEntry objects; FileShare.ReadWrite|Delete; -InitialLines, -FollowRollover, -PollIntervalMs, -Duration, -MaxEntries; in-stream filters -Method/-Status/-UriLike/-ClientIP/-MinStatus (#52).
- feat(iis): add Get-IISFailedRequestTrace — parse FREB fr######.xml files into typed PSWinOps.IISFailedRequestTrace objects; auto-resolves FREB folder per site; surfaces URL/verb/statusCode/subStatus/timeTaken/appPool/worker PID/failureReason plus first ERROR/WARNING event; -After/-Before/-StatusCode/-FailureReason filters, -Tail, -IncludeEvents (#53).
- feat(iis): add Get-IISCertificateBinding — read-only inventory of IIS HTTPS bindings joined to their presented X509 certificate; SiteName, BindingInformation, Protocol, SslFlags (SNI/CCS), Thumbprint, Subject, SAN, Issuer, NotBefore/NotAfter, DaysUntilExpiration, Expired, CertificateStore, HasPrivateKey; -SiteName/-HostHeader/-Thumbprint/-Port filters, -ExpiringInDays, -IncludeExpired (#54).
- feat(iis): add Test-IISBindingCertificate — read-only auditor running six independent checks per binding (expiration vs Warning/Critical thresholds, X509Chain.Build, hostname/SAN match, HasPrivateKey, signature/key-algorithm strength, CertStoreName alignment); emits PSWinOps.IISCertificateBindingTestResult with OverallStatus and Findings array; -WarningDays/-CriticalDays, -SkipChainValidation, -IncludeRevocationCheck (#55).
- feat(iis): add Get-IISAppPoolHistory — reconstructs app pool lifecycle (recycles, rapid-fail shutdowns, crashes, start/stop, identity changes, orphaned workers) by mining System (Microsoft-Windows-WAS), Application (W3SVC-WP) and optionally IIS-W3SVC-WP/Operational event logs; classifies events via a 16-entry EventId map into typed PSWinOps.IISAppPoolHistoryEvent rows with AppPoolName, WorkerPid, normalised ReasonCode, UTC/local timestamps; server-side -After/-Before/-EventId, client-side -AppPoolName wildcard, -Tail, -IncludeOperationalLog (#56).
- feat(format): TableControl views for all new typed outputs in PSWinOps.Format.ps1xml.
### Changed
- refactor: automated remediation chain — quality, testability & monitor extraction (ITER 1-8).
### Fixed
- fix(tests): import PSWinOps.psd1 explicitly in Set-NTPClient.Tests.

## 0.0.17 - 2026-04-02
- refactor: Invoke-RemoteOrLocal rewrite (#30)
- refactor: move OverallHealth computation to process{} block (#31)
- fix: misc cleanup — synopsis, #Requires, module-scoped local names (#32)
- feat: add about_PSWinOps help file and PSWinOpsHealthStatus enum (#33)
- feat: add Get-ExchangeServerHealth healthcheck function (#34)
- fix: replace Clear-Host with Console.SetCursorPosition (#35)
- fix/docs: audit coherence documentation (#36)
- docs: fix documentation audit findings - Axis 1 (#37)
- fix: coherence Axis 2 (#38)

## 0.0.16 - 2026-03-31
- feat(format): add TableControl default views for all typed outputs (#29)

## 0.0.15 - 2026-03-31
- fix: miscellaneous fixes (#25)
- fix(ntp): NTP function fixes (#27)
- feat: new functions and expanded test coverage (#28)

## 0.0.14 - 2026-03-26
- fix: miscellaneous fixes (#25)

## 0.0.13 - 2026-03-25
- refactor: rename folder structure (#19)
- feat(tests): new Pester tests (#20)
- perf: optimization pass (#22)
- feat: general improvements (#23)
- refactor: coherence pass (#24)

## 0.0.12 - 2026-03-24
- refactor: rename folder structure (#19)
- feat(tests): new Pester tests (#20)
- perf: optimization pass (#22)

## 0.0.11 - 2026-03-24
- refactor: rename folder structure (#19)

## 0.0.10 - 2026-03-23
- perf: optimization pass (#15)
- feat(proxy): add Get-ProxyConfiguration (#16)
- feat: general improvements (#17)
- feat: first audit commit (#18)

## 0.0.9 - 2026-03-23
- perf: optimization pass (#15)

## 0.0.8 - 2026-03-22
- fix: minor fixes (#14)

## 0.0.7 - 2026-03-22
- fix: remove useless property (#8)
- feat(system): add Get-ComputerUptime (#9)
- feat(system): add Get-SystemSummary (#10)
- feat: general improvements (#11)
- feat(system): add Get-PendingReboot (#12)
- feat: PSTypeName on all outputs (#13)

## 0.0.6 - 2026-03-21
- fix: remove useless property (#8)
- feat(system): add Get-ComputerUptime (#9)

## 0.0.5 - 2026-03-21
- Minor improvements

## 0.0.4 - 2026-03-20
- fix: fixed function (#5)
- fix(rdp): fixed sessions functions (#6)
- feat(ntp): add Test-NTPSync (#7)

## 0.0.3 - 2026-03-20
- Minor improvements

## 0.0.2 - 2026-03-19
- feat(ci): new CI pipeline (#1)
- feat(utils): add ConvertFrom-MisencodedString (#2)
- feat(rdp): add Get-RdpSessionHistory (#3)
- feat(rdp): add sessions functions (#4)
