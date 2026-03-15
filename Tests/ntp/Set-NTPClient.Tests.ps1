#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester v5 unit tests for Set-NTPClient.ps1 (v2.0.0)

.NOTES
    Prérequis : session PowerShell élevée (Admin) pour le dot-sourcing.
    Exécution :
        Invoke-Pester -Path .\Set-NTPClient.Tests.ps1 -Output Detailed

    Note : w32tm.exe (avec .exe explicite, step 4) n'est pas intercepté par
    Mock w32tm car PowerShell résout les Application différemment des Function.
    Pour une testabilité complète, utiliser 'w32tm' (sans .exe) de façon
    cohérente dans le script source.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot 'Set-NTPClient.ps1'
    if (-not (Test-Path $scriptPath)) { throw "Script introuvable : $scriptPath" }
    . $scriptPath
}

Describe 'Set-NTPClient' -Tag 'Unit' {

    # ──────────────────────────────────────────────────────────────────────────
    # Mocks partagés – réinitialisés avant chaque test
    # ──────────────────────────────────────────────────────────────────────────
    BeforeEach {
        # Services
        Mock Get-Service     { [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' } }
        Mock Start-Service   {}
        Mock Restart-Service {}
        Mock Start-Sleep     {}

        # Registre
        Mock Test-Path        { $true }
        Mock Set-ItemProperty {}

        # Exécutable w32tm (appels directs hors job)
        Mock w32tm {
            $a = $args -join ' '
            if ($a -match '/register')             { return '' }
            if ($a -match '/config')               { return '' }
            if ($a -match '/query.*configuration') {
                return @(
                    'NtpServer: ntp1.ecritel.net,0x9 ntp2.ecritel.net,0x9 (Local)',
                    'Type: NTP (Local)'
                )
            }
            if ($a -match '/query.*status') {
                return @(
                    'Source: ntp1.ecritel.net,0x9',
                    'Last Successful Sync Time: 20/02/2026 19:00:00'
                )
            }
            return ''
        }

        # Job Step 7 : w32tm /resync uniquement (1 seul job dans la version actuelle)
        Mock Start-Job {
            [PSCustomObject]@{ Id = 1; State = 'Completed' }
        }
        Mock Wait-Job {
            param($Job, $Timeout)
            $Job
        }
        Mock Receive-Job {
            param($Job, [switch]$Keep)
            if ($Keep) { return "La commande s'est déroulée correctement." }
            return ''
        }
        Mock Remove-Job {}
        Mock Stop-Job   {}
    }

    # ==========================================================================
    Describe '1. Validation des paramètres' {
    # ==========================================================================

        Context 'NtpServers' {
            It 'Accepte un serveur valide' {
                { Set-NTPClient -NtpServers 'time.windows.com' -Confirm:$false } |
                    Should -Not -Throw
            }
            It 'Accepte plusieurs serveurs valides' {
                { Set-NTPClient -NtpServers 'ntp1.ecritel.net', 'ntp2.ecritel.net' -Confirm:$false } |
                    Should -Not -Throw
            }
            It 'Rejette une valeur null' {
                { Set-NTPClient -NtpServers $null -Confirm:$false } | Should -Throw
            }
            It 'Rejette une chaîne vide' {
                { Set-NTPClient -NtpServers '' -Confirm:$false } | Should -Throw
            }
        }

        Context 'MaxPhaseOffset [1..3600]' {
            It 'Accepte la valeur minimale (1)' {
                { Set-NTPClient -MaxPhaseOffset 1 -Confirm:$false } | Should -Not -Throw
            }
            It 'Accepte la valeur maximale (3600)' {
                { Set-NTPClient -MaxPhaseOffset 3600 -Confirm:$false } | Should -Not -Throw
            }
            It 'Rejette 0 (en dessous du min)' {
                { Set-NTPClient -MaxPhaseOffset 0 -Confirm:$false } | Should -Throw
            }
            It 'Rejette 3601 (au dessus du max)' {
                { Set-NTPClient -MaxPhaseOffset 3601 -Confirm:$false } | Should -Throw
            }
        }

        Context 'SpecialPollInterval [1..86400]' {
            It 'Accepte la valeur minimale (1)' {
                { Set-NTPClient -SpecialPollInterval 1 -Confirm:$false } | Should -Not -Throw
            }
            It 'Accepte la valeur maximale (86400)' {
                { Set-NTPClient -SpecialPollInterval 86400 -Confirm:$false } | Should -Not -Throw
            }
            It 'Rejette 0' {
                { Set-NTPClient -SpecialPollInterval 0 -Confirm:$false } | Should -Throw
            }
            It 'Rejette 86401' {
                { Set-NTPClient -SpecialPollInterval 86401 -Confirm:$false } | Should -Throw
            }
        }

        Context 'MinPollInterval [0..17]' {
            It 'Accepte 0' {
                { Set-NTPClient -MinPollInterval 0 -MaxPollInterval 1 -Confirm:$false } |
                    Should -Not -Throw
            }
            It 'Accepte 17' {
                { Set-NTPClient -MinPollInterval 16 -MaxPollInterval 17 -Confirm:$false } |
                    Should -Not -Throw
            }
            It 'Rejette 18' {
                { Set-NTPClient -MinPollInterval 18 -Confirm:$false } | Should -Throw
            }
        }

        Context 'MaxPollInterval [0..17]' {
            It 'Accepte 17' {
                { Set-NTPClient -MinPollInterval 16 -MaxPollInterval 17 -Confirm:$false } |
                    Should -Not -Throw
            }
            It 'Rejette 18' {
                { Set-NTPClient -MaxPollInterval 18 -Confirm:$false } | Should -Throw
            }
        }

        Context 'Cross-validation MaxPollInterval > MinPollInterval' {
            It 'Lève une exception si MaxPollInterval égale MinPollInterval' {
                { Set-NTPClient -MinPollInterval 6 -MaxPollInterval 6 -Confirm:$false } |
                    Should -Throw -ExpectedMessage '*MaxPollInterval*greater than*MinPollInterval*'
            }
            It 'Lève une exception si MaxPollInterval est inférieur à MinPollInterval' {
                { Set-NTPClient -MinPollInterval 10 -MaxPollInterval 6 -Confirm:$false } |
                    Should -Throw -ExpectedMessage '*MaxPollInterval*greater than*MinPollInterval*'
            }
            It 'Ne lève pas d''exception si MaxPollInterval est strictement supérieur' {
                { Set-NTPClient -MinPollInterval 6 -MaxPollInterval 10 -Confirm:$false } |
                    Should -Not -Throw
            }
        }
    }

    # ==========================================================================
    Describe '2. Valeurs par défaut des paramètres' {
    # ==========================================================================

        It 'NtpServers par défaut contient ntp1.ecritel.net' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'NtpServer' -and $Value -like '*ntp1.ecritel.net*'
            }
        }
        It 'NtpServers par défaut contient ntp2.ecritel.net' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'NtpServer' -and $Value -like '*ntp2.ecritel.net*'
            }
        }
        It 'MaxPhaseOffset par défaut = 1' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'MaxAllowedPhaseOffset' -and $Value -eq 1
            }
        }
        It 'SpecialPollInterval par défaut = 300' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'SpecialPollInterval' -and $Value -eq 300
            }
        }
        It 'MinPollInterval par défaut = 6' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'MinPollInterval' -and $Value -eq 6
            }
        }
        It 'MaxPollInterval par défaut = 10' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'MaxPollInterval' -and $Value -eq 10
            }
        }
    }

    # ==========================================================================
    Describe '3. Gestion du service W32Time' {
    # ==========================================================================

        It 'Interroge le service w32time au démarrage' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Get-Service -Times 1 -ParameterFilter { $Name -eq 'w32time' }
        }
        It 'Ne démarre PAS le service s''il est déjà Running' {
            Mock Get-Service { [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' } }
            Set-NTPClient -Confirm:$false
            Should -Invoke Start-Service -Times 0
        }
        It 'Démarre le service s''il est Stopped' {
            Mock Get-Service { [PSCustomObject]@{ Name = 'w32time'; Status = 'Stopped' } }
            Set-NTPClient -Confirm:$false
            Should -Invoke Start-Service -Times 1 -ParameterFilter { $Name -eq 'w32time' }
        }
        It 'Enregistre le service via w32tm /register s''il est absent' {
            $call = 0
            Mock Get-Service {
                $call++
                if ($call -eq 1) { return $null }
                return [PSCustomObject]@{ Name = 'w32time'; Status = 'Running' }
            }
            Set-NTPClient -Confirm:$false
            Should -Invoke w32tm -Times 1 -ParameterFilter { $args -contains '/register' }
        }
        It 'Redémarre le service après configuration' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Restart-Service -Times 1 -ParameterFilter { $Name -eq 'w32time' }
        }
    }

    # ==========================================================================
    Describe '4. Vérification des chemins registre (3 chemins)' {
    # ==========================================================================

        It 'Vérifie exactement 3 chemins registre' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Test-Path -Times 3
        }
        It 'Lève une exception si la clé Config est absente' {
            Mock Test-Path { param($Path); $Path -notlike '*\Config' }
            { Set-NTPClient -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Registry key not found*'
        }
        It 'Lève une exception si la clé NtpClient est absente' {
            Mock Test-Path { param($Path); $Path -notlike '*\NtpClient' }
            { Set-NTPClient -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Registry key not found*'
        }
        It 'Lève une exception si la clé Parameters est absente' {
            Mock Test-Path { param($Path); $Path -notlike '*\Parameters' }
            { Set-NTPClient -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Registry key not found*'
        }
    }

    # ==========================================================================
    Describe '5. Construction de la liste de serveurs NTP' {
    # ==========================================================================

        It 'Ajoute le flag 0x9 aux serveurs sans flag existant' {
            Set-NTPClient -NtpServers 'ntp1.ecritel.net', 'ntp2.ecritel.net' -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'NtpServer' -and
                $Value -eq 'ntp1.ecritel.net,0x9 ntp2.ecritel.net,0x9'
            }
        }
        It 'Préserve un flag existant' {
            Set-NTPClient -NtpServers 'ntp1.ecritel.net,0x1' -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'NtpServer' -and $Value -eq 'ntp1.ecritel.net,0x1'
            }
        }
        It 'Gère un mix : flag existant + flag par défaut' {
            Set-NTPClient -NtpServers 'ntp1.ecritel.net,0x8', 'ntp2.ecritel.net' -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'NtpServer' -and
                $Value -eq 'ntp1.ecritel.net,0x8 ntp2.ecritel.net,0x9'
            }
        }
        It 'Gère un serveur unique sans flag' {
            Set-NTPClient -NtpServers 'time.windows.com' -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'NtpServer' -and $Value -eq 'time.windows.com,0x9'
            }
        }
        It 'Sépare les serveurs par un espace' {
            Set-NTPClient -NtpServers 'a.test', 'b.test', 'c.test' -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'NtpServer' -and ($Value -split ' ').Count -eq 3
            }
        }
    }

    # ==========================================================================
    Describe '6. Écriture registre – 6 appels Set-ItemProperty attendus' {
    # ==========================================================================

        It 'Effectue exactement 6 appels Set-ItemProperty' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 6 -Exactly
        }

        # ── Step 4 : NTP config (Parameters + Config) ─────────────────────────
        It '[Step4] Écrit NtpServer dans HKLM:\...\Parameters' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Path -like '*\Parameters' -and $Name -eq 'NtpServer'
            }
        }
        It '[Step4] Écrit Type = NTP dans HKLM:\...\Parameters' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Path -like '*\Parameters' -and $Name -eq 'Type' -and $Value -eq 'NTP'
            }
        }
        It '[Step4] Écrit MaxAllowedPhaseOffset dans HKLM:\...\Config' {
            Set-NTPClient -MaxPhaseOffset 5 -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Path -like '*\Config' -and $Name -eq 'MaxAllowedPhaseOffset' -and $Value -eq 5
            }
        }

        # ── Step 5 : Poll intervals ────────────────────────────────────────────
        It '[Step5] Écrit SpecialPollInterval dans HKLM:\...\NtpClient' {
            Set-NTPClient -SpecialPollInterval 600 -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Path -like '*\NtpClient' -and $Name -eq 'SpecialPollInterval' -and $Value -eq 600
            }
        }
        It '[Step5] Écrit MinPollInterval dans HKLM:\...\Config' {
            Set-NTPClient -MinPollInterval 7 -MaxPollInterval 12 -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Path -like '*\Config' -and $Name -eq 'MinPollInterval' -and $Value -eq 7
            }
        }
        It '[Step5] Écrit MaxPollInterval dans HKLM:\...\Config' {
            Set-NTPClient -MinPollInterval 7 -MaxPollInterval 12 -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Path -like '*\Config' -and $Name -eq 'MaxPollInterval' -and $Value -eq 12
            }
        }
    }

    # ==========================================================================
    Describe '7. Synchronisation NTP (Step 7 – w32tm /resync)' {
    # ==========================================================================

        It 'Lance exactement 1 job background (resync uniquement)' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Start-Job -Times 1 -Exactly
        }
        It 'Nettoie le job avec Remove-Job après exécution' {
            Set-NTPClient -Confirm:$false
            Should -Invoke Remove-Job -Times 1
        }
        It 'N''émet PAS de warning si le message FR de succès est retourné' {
            Mock Receive-Job {
                param($Job, [switch]$Keep)
                if ($Keep) { return "La commande s'est déroulée correctement." }
            }
            $warnings = $null
            Set-NTPClient -Confirm:$false -WarningVariable warnings
            ($warnings | Where-Object { $_ -match 'synchronization may have failed' }) |
                Should -BeNullOrEmpty
        }
        It 'N''émet PAS de warning si le message EN de succès est retourné' {
            Mock Receive-Job {
                param($Job, [switch]$Keep)
                if ($Keep) { return 'The command completed successfully.' }
            }
            $warnings = $null
            Set-NTPClient -Confirm:$false -WarningVariable warnings
            ($warnings | Where-Object { $_ -match 'synchronization may have failed' }) |
                Should -BeNullOrEmpty
        }
        It 'Émet un warning si la sortie ne contient aucun message de succès' {
            Mock Receive-Job {
                param($Job, [switch]$Keep)
                if ($Keep) { return 'Error: peer unreachable' }
            }
            $warnings = $null
            Set-NTPClient -Confirm:$false -WarningVariable warnings
            ($warnings | Where-Object { $_ -match 'synchronization may have failed' }) |
                Should -Not -BeNullOrEmpty
        }
    }

    # ==========================================================================
    Describe '8. SupportsShouldProcess / -WhatIf' {
    # ==========================================================================

        It 'N''écrit rien en registre avec -WhatIf' {
            Set-NTPClient -WhatIf
            Should -Invoke Set-ItemProperty -Times 0
        }
        It 'Ne redémarre pas le service avec -WhatIf' {
            Set-NTPClient -WhatIf
            Should -Invoke Restart-Service -Times 0
        }
        It 'Ne lance aucun job avec -WhatIf' {
            Set-NTPClient -WhatIf
            Should -Invoke Start-Job -Times 0
        }
        It 'Ne démarre pas le service avec -WhatIf, même s''il est Stopped' {
            Mock Get-Service { [PSCustomObject]@{ Name = 'w32time'; Status = 'Stopped' } }
            Set-NTPClient -WhatIf
            Should -Invoke Start-Service -Times 0
        }
    }

    # ==========================================================================
    Describe '9. Gestion des erreurs' {
    # ==========================================================================

        It 'Propage UnauthorizedAccessException depuis Set-ItemProperty' {
            Mock Set-ItemProperty {
                throw [System.UnauthorizedAccessException]::new('Accès refusé au registre')
            }
            { Set-NTPClient -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Accès refusé*'
        }
        It 'Propage InvalidOperationException depuis Restart-Service' {
            Mock Restart-Service {
                throw [System.InvalidOperationException]::new('Impossible de redémarrer le service')
            }
            { Set-NTPClient -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Impossible de redémarrer*'
        }
        It 'Propage toute exception inattendue' {
            Mock Set-ItemProperty {
                throw [System.Exception]::new('Erreur inattendue')
            }
            { Set-NTPClient -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Erreur inattendue*'
        }
        It 'Lève une exception si un chemin registre est manquant' {
            Mock Test-Path { $false }
            { Set-NTPClient -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Registry key not found*'
        }
        It 'Propage l''exception si Get-Service échoue en mode Stop' {
            $call = 0
            Mock Get-Service {
                $call++
                if ($call -eq 1) { return $null }
                throw [System.Exception]::new('Impossible de trouver le service w32time')
            }
            { Set-NTPClient -Confirm:$false } |
                Should -Throw -ExpectedMessage '*w32time*'
        }
    }
}