ï»¿#Requires -Version 5.1

<#
    Health status values returned by the 15 healthcheck functions.
    Defined as an enum so consumers can reference values as:
        [PSWinOpsHealthStatus]::Healthy
        [PSWinOpsHealthStatus]::Critical
#>
enum PSWinOpsHealthStatus {
    Healthy
    Degraded
    Critical
    RoleUnavailable
    InsufficientPrivilege
    Unknown
}
