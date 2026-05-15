# PSWinOps

A collection of PowerShell utilities for Windows system administrators.

[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](https://microsoft.com/powershell)
[![Publish](https://github.com/k9fr4n/PSWinOps/actions/workflows/publish.yml/badge.svg)](https://github.com/k9fr4n/PSWinOps/actions/workflows/publish.yml)
[![PSGallery Version](https://img.shields.io/powershellgallery/v/PSWinOps)](https://www.powershellgallery.com/packages/PSWinOps)
[![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/PSWinOps)](https://www.powershellgallery.com/packages/PSWinOps)
[![GitHub Release](https://img.shields.io/github/v/release/k9fr4n/PSWinOps)](https://github.com/k9fr4n/PSWinOps/releases)
[![CI](https://github.com/k9fr4n/PSWinOps/actions/workflows/ci.yml/badge.svg)](https://github.com/k9fr4n/PSWinOps/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/k9fr4n/PSWinOps/graph/badge.svg?token=B269KNRXTN)](https://codecov.io/gh/k9fr4n/PSWinOps)

## Installation

```powershell
Install-Module -Name PSWinOps -Repository PSGallery
```

## Requirements

- PowerShell 5.1+
- Windows OS

## Usage

```powershell
Import-Module PSWinOps

# List available commands
Get-Command -Module PSWinOps
```

## Optional Dependencies

PSWinOps lazy-imports the following modules on demand. They are **not** listed in
`RequiredModules` so the module remains loadable on hosts that only need a subset of
its surface. Install only what you use.

| Domain | PSWinOps Functions | Module(s) | How to install |
|---|---|---|---|
| Active Directory | `Get-AD*`, `Enable/Disable/Unlock-ADUserAccount`, `Reset-ADUserPassword`, `Invoke-ADSecurityAudit`, `Search-ADObject`, `Get-AdDomainControllerHealth` | `ActiveDirectory` | `Install-WindowsFeature RSAT-AD-PowerShell` |
| IIS (classic pipeline) | `Get-IISHealth`, `Set-IISBindingCertificate` | `WebAdministration` | `Install-WindowsFeature Web-Scripting-Tools` (Server) |
| IIS (modern) | `Get-IISHealth`, `Set-IISBindingCertificate` | `IISAdministration` | `Install-Module IISAdministration` (PSGallery) |
| Hyper-V | `Get-HyperVHostHealth` | `Hyper-V` | `Install-WindowsFeature Hyper-V-PowerShell` |
| Failover Clusters | `Get-ClusterHealth` | `FailoverClusters` | `Install-WindowsFeature RSAT-Clustering-PowerShell` |
| DHCP | `Get-DhcpServerHealth` | `DhcpServer` | `Install-WindowsFeature RSAT-DHCP` |
| DNS Server | `Get-DnsServerHealth` | `DnsServer` | `Install-WindowsFeature RSAT-DNS-Server` |
| File Server (FSRM) | `Get-FileServerHealth` | `FileServerResourceManager` | `Install-WindowsFeature FS-Resource-Manager` |
| Exchange | `Get-ExchangeServerHealth` | `ExchangeManagementShell` (module) or `Microsoft.Exchange.Management.PowerShell.SnapIn` (snapin, Desktop only) | Exchange Management Tools (shipped with Exchange Server) |
| Remote Desktop Services | `Get-RDSHealth` | `RemoteDesktop` | `Install-WindowsFeature RSAT-RDS-Tools` |
| WSUS | `Get-WSUSHealth` | `UpdateServices` | `Install-WindowsFeature RSAT-UpdateServices` |
| AD FS | `Get-ADFSHealth` | `ADFS` | `Install-WindowsFeature ADFS-Federation` or `RSAT-ADFS` |
| Print Server | `Get-PrintServerHealth` | `PrintManagement` | `Install-WindowsFeature Print-Services` (built-in on Server) |
| DFS Namespace | `Get-DfsNamespaceHealth` | `DFSN` | `Install-WindowsFeature RSAT-DFS-Mgmt-Con` |

> **Note:** `Get-DfsReplicationHealth` and `Get-CertificateAuthorityHealth` use CIM/WMI
> directly and do not require an external PowerShell module — only the corresponding
> Windows role/service must be running on the target computer.

## Contributing

1. Fork the repo
2. Create a feature branch
3. Submit a Pull Request

## License

MIT
