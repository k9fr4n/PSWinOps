#Requires -Version 5.1

function Get-ADComputerDetail {
    <#
    .SYNOPSIS
        Retrieves detailed Active Directory computer account information

    .DESCRIPTION
        Queries Active Directory for comprehensive computer account details including
        operating system, network information, group membership count, and organizational unit.
        Supports pipeline input for processing multiple computer identities at once.

    .PARAMETER Identity
        One or more computer identities to query. Accepts computer name or DistinguishedName.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADComputerDetail -Identity 'SRV01'

        Retrieves detailed information for the computer account SRV01.

    .EXAMPLE
        Get-ADComputerDetail -Identity 'SRV01' -Server 'dc01.contoso.com'

        Retrieves computer details from a specific domain controller.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-ADComputerDetail

        Retrieves details for multiple computers via pipeline input.

    .OUTPUTS
        PSWinOps.ADComputerDetail
        Returns a custom object with comprehensive computer account properties including
        operating system, network details, group membership count, and organizational unit.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-03
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adcomputer
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

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
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop
        }
        catch {
            throw "[$($MyInvocation.MyCommand)] Failed to import ActiveDirectory module: $_"
        }

        $adParams = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adParams['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adParams['Credential'] = $Credential
        }

        $adProperties = @(
            'DNSHostName'
            'Description'
            'OperatingSystem'
            'OperatingSystemVersion'
            'OperatingSystemServicePack'
            'IPv4Address'
            'Enabled'
            'LastLogonDate'
            'WhenCreated'
            'WhenChanged'
            'MemberOf'
            'DistinguishedName'
            'ServicePrincipalNames'
            'Location'
        )
    }

    process {
        foreach ($identityValue in $Identity) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying computer: $identityValue"

                $computer = Get-ADComputer -Identity $identityValue -Properties $adProperties @adParams -ErrorAction Stop

                [PSCustomObject]@{
                    PSTypeName             = 'PSWinOps.ADComputerDetail'
                    Name                   = $computer.Name
                    DNSHostName            = $computer.DNSHostName
                    Description            = $computer.Description
                    OperatingSystem        = $computer.OperatingSystem
                    OperatingSystemVersion = $computer.OperatingSystemVersion
                    IPv4Address            = $computer.IPv4Address
                    Enabled                = $computer.Enabled
                    LastLogonDate          = $computer.LastLogonDate
                    WhenCreated            = $computer.WhenCreated
                    WhenChanged            = $computer.WhenChanged
                    Location               = $computer.Location
                    MemberOfCount          = if ($computer.MemberOf) { @($computer.MemberOf).Count } else { 0 }
                    SPNCount               = if ($computer.ServicePrincipalNames) { @($computer.ServicePrincipalNames).Count } else { 0 }
                    OrganizationalUnit     = ($computer.DistinguishedName -replace '^CN=[^,]+,')
                    DistinguishedName      = $computer.DistinguishedName
                    Timestamp              = Get-Date -Format 'o'
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query computer '$identityValue': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
