#Requires -Version 5.1

function Get-ADDomainInfo {
    <#
    .SYNOPSIS
        Retrieves a comprehensive summary of an Active Directory domain

    .DESCRIPTION
        Returns the identity card of an Active Directory domain including functional levels,
        FSMO role holders, domain controller inventory, site topology, object counts (users,
        computers, groups, OUs), and password policy. Designed as the first command to run
        when discovering an unfamiliar domain. All data is gathered from a single domain
        context using standard AD cmdlets.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to. When omitted,
        the current domain is used.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory queries.

    .EXAMPLE
        Get-ADDomainInfo

        Returns a full summary of the current domain.

    .EXAMPLE
        Get-ADDomainInfo -Server 'dc01.contoso.com'

        Returns domain information from a specific domain controller.

    .EXAMPLE
        Get-ADDomainInfo -Server 'child.contoso.com' -Credential (Get-Credential)

        Returns domain information for a child domain using alternate credentials.

    .OUTPUTS
        PSWinOps.ADDomainInfo
        Returns a single object with domain identity, functional levels, FSMO holders,
        DC list, site names, object counts, and default password policy.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-addomain
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ActiveDirectory module is not available: $_"
            return
        }

        $adSplat = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adSplat['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adSplat['Credential'] = $Credential
        }
    }

    process {
        try {
            # --- Domain ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying domain"
            $domain = Get-ADDomain -ErrorAction Stop @adSplat

            # --- Forest ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying forest"
            $forest = Get-ADForest -ErrorAction Stop @adSplat

            # --- Domain Controllers ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying domain controllers"
            $domainControllers = Get-ADDomainController -Filter * -ErrorAction Stop @adSplat

            $dcList = $domainControllers | ForEach-Object {
                [PSCustomObject]@{
                    HostName        = $_.HostName
                    Site            = $_.Site
                    IPv4Address     = $_.IPv4Address
                    IsGlobalCatalog = $_.IsGlobalCatalog
                    IsReadOnly      = $_.IsReadOnly
                    OperatingSystem = $_.OperatingSystem
                }
            }

            # --- Sites ---
            $sites = ($domainControllers | Select-Object -ExpandProperty 'Site' -Unique | Sort-Object) -join ', '

            # --- Object counts ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Counting domain objects"
            $domainDN = $domain.DistinguishedName

            $countSplat = @{ SearchBase = $domainDN; ErrorAction = 'Stop' }

            $enabledUsers = @(Get-ADUser -Filter "Enabled -eq `$true" @countSplat @adSplat).Count
            $disabledUsers = @(Get-ADUser -Filter "Enabled -eq `$false" @countSplat @adSplat).Count
            $enabledComputers = @(Get-ADComputer -Filter "Enabled -eq `$true" @countSplat @adSplat).Count
            $disabledComputers = @(Get-ADComputer -Filter "Enabled -eq `$false" @countSplat @adSplat).Count
            $groupCount = @(Get-ADGroup -Filter * @countSplat @adSplat).Count
            $ouCount = @(Get-ADOrganizationalUnit -Filter * @countSplat @adSplat).Count

            # --- Default Password Policy ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying default password policy"
            $passwordPolicy = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop @adSplat

            # --- Fine-Grained Password Policies count ---
            $fgppCount = 0
            try {
                $fgppCount = @(Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction Stop @adSplat).Count
            }
            catch {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Could not query FGPP: $_"
            }

            # --- Recycle Bin ---
            $recycleBinEnabled = $false
            try {
                $optionalFeatures = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" -ErrorAction Stop @adSplat
                if ($optionalFeatures -and $optionalFeatures.EnabledScopes.Count -gt 0) {
                    $recycleBinEnabled = $true
                }
            }
            catch {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Could not query optional features: $_"
            }

            [PSCustomObject]@{
                PSTypeName                  = 'PSWinOps.ADDomainInfo'
                DomainName                  = $domain.DNSRoot
                NetBIOSName                 = $domain.NetBIOSName
                DistinguishedName           = $domain.DistinguishedName
                DomainFunctionalLevel       = $domain.DomainMode.ToString()
                ForestFunctionalLevel       = $forest.ForestMode.ToString()
                ForestName                  = $forest.Name
                # FSMO Roles
                PDCEmulator                 = $domain.PDCEmulator
                RIDMaster                   = $domain.RIDMaster
                InfrastructureMaster        = $domain.InfrastructureMaster
                SchemaMaster                = $forest.SchemaMaster
                DomainNamingMaster          = $forest.DomainNamingMaster
                # Domain Controllers
                DomainControllerCount       = $domainControllers.Count
                DomainControllers           = $dcList
                Sites                       = $sites
                # Object counts
                EnabledUsers                = $enabledUsers
                DisabledUsers               = $disabledUsers
                TotalUsers                  = $enabledUsers + $disabledUsers
                EnabledComputers            = $enabledComputers
                DisabledComputers           = $disabledComputers
                TotalComputers              = $enabledComputers + $disabledComputers
                GroupCount                  = $groupCount
                OUCount                     = $ouCount
                # Password Policy
                MinPasswordLength           = $passwordPolicy.MinPasswordLength
                MaxPasswordAgeDays          = [math]::Round($passwordPolicy.MaxPasswordAge.TotalDays)
                MinPasswordAgeDays          = [math]::Round($passwordPolicy.MinPasswordAge.TotalDays)
                PasswordHistoryCount        = $passwordPolicy.PasswordHistoryCount
                ComplexityEnabled           = $passwordPolicy.ComplexityEnabled
                ReversibleEncryption        = $passwordPolicy.ReversibleEncryptionEnabled
                LockoutThreshold            = $passwordPolicy.LockoutThreshold
                LockoutDurationMinutes      = [math]::Round($passwordPolicy.LockoutDuration.TotalMinutes)
                LockoutObservationMinutes   = [math]::Round($passwordPolicy.LockoutObservationWindow.TotalMinutes)
                FineGrainedPolicyCount      = $fgppCount
                # Features
                RecycleBinEnabled           = $recycleBinEnabled
                Timestamp                   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            }
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to retrieve domain information: $_"
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
