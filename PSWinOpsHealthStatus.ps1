#Requires -Version 5.1

<#
    .SYNOPSIS
        Enum defining standardised health status values for PSWinOps healthcheck functions.

    .DESCRIPTION
        PSWinOpsHealthStatus is an enumeration used by the 15 healthcheck functions
        (Get-AdDomainControllerHealth, Get-ADFSHealth, Get-ClusterHealth, etc.) to
        express the overall health of a server role in a machine-comparable way.

        Consumers can reference values as typed constants:
            [PSWinOpsHealthStatus]::Healthy
            [PSWinOpsHealthStatus]::Critical

        Members:
            Healthy               — All checks passed; the role is fully operational.
            Degraded              — One or more non-critical checks failed; the role
                                    is operational but requires attention.
            Critical              — One or more critical checks failed; the role is
                                    non-functional or at risk of imminent failure.
            RoleUnavailable       — The target role or feature is not installed on the
                                    machine (e.g. DHCP tools missing).
            InsufficientPrivilege — The current user lacks the permissions needed to
                                    perform the health checks.
            Unknown               — The health status could not be determined (e.g.
                                    unexpected error during evaluation).

    .NOTES
        Author:        Franck SALLET
        Version:       1.1.0
        Last Modified: 2026-04-02
        Requires:      PowerShell 5.1+ / Windows only
#>
enum PSWinOpsHealthStatus {
    Healthy
    Degraded
    Critical
    RoleUnavailable
    InsufficientPrivilege
    Unknown
}
