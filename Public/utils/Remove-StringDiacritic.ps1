#Requires -Version 5.1

function Remove-StringDiacritic {
    <#
        .SYNOPSIS
            Remove diacritical marks from a string using Unicode NFD normalization

        .DESCRIPTION
            Normalizes the input string to Unicode NFD (Decomposed) form, strips all
            Non-Spacing Mark characters (accents, cedillas, umlauts, tildes, etc.),
            then recomposes the result to NFC form. The function is pure .NET and
            runs on any platform; no Windows dependency or elevation is required.

        .PARAMETER String
            The string from which diacritical marks will be removed.
            Accepts pipeline input by value.

        .EXAMPLE
            Remove-StringDiacritic -String 'Héllo Wörld'
            Returns 'Hello World' — strips the acute accent and umlaut.

        .EXAMPLE
            'François' | Remove-StringDiacritic
            Pipeline with a single string; returns 'Francois'.

        .EXAMPLE
            'Ångström', 'naïve', 'señor', 'Ünîcödé' | Remove-StringDiacritic
            Pipeline with multiple strings; returns each string with diacritics removed.

        .OUTPUTS
            System.String
            The input string with all diacritical marks removed.

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-06-24
            Requires:      PowerShell 5.1+
            Permissions:   None required

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/dotnet/api/system.string.normalize
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$String
    )
    process {
        if ($PSCmdlet.ShouldProcess($String, 'Remove diacritics')) {
            $normalized = $String.Normalize([Text.NormalizationForm]::FormD)
            $sb = [Text.StringBuilder]::new()
            foreach ($char in $normalized.ToCharArray()) {
                if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne
                    [Globalization.UnicodeCategory]::NonSpacingMark) {
                    [void]$sb.Append($char)
                }
            }
            $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
        }
    }
}
