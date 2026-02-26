function ConvertFrom-MisencodedString {
    <#
.SYNOPSIS
    Converts a misencoded string by reinterpreting bytes from a source encoding

.DESCRIPTION
    Fixes encoding issues where text was incorrectly interpreted using the wrong
    character encoding. The function takes the string, converts it to bytes using
    the source encoding (default: Cyrillic), then reinterprets those bytes as
    ASCII or another target encoding.

    This is commonly needed when text was stored or transmitted using one encoding
    but displayed or processed as another, resulting in garbled characters.

.PARAMETER String
    The misencoded string to convert. Accepts input from the pipeline.
    Empty strings are allowed and will be returned unchanged.

.PARAMETER SourceEncoding
    The encoding that was incorrectly applied to the original text.
    Default is 'Cyrillic' (windows-1251). Common values include 'Cyrillic',
    'windows-1252', 'iso-8859-1', 'utf-8'.

.PARAMETER TargetEncoding
    The encoding to use when reinterpreting the bytes.
    Default is 'ASCII'. Use 'utf-8' for broader character support.

.EXAMPLE
    ConvertFrom-MisencodedString -String 'portal'

    Converts a Cyrillic-misencoded string back to readable ASCII text.
    Returns the corrected string.

.EXAMPLE
    'portal', 'server' | ConvertFrom-MisencodedString

    Pipeline example: processes multiple misencoded strings and returns
    the corrected versions.

.EXAMPLE
    ConvertFrom-MisencodedString -String 'cafe' -SourceEncoding 'windows-1252' -TargetEncoding 'utf-8'

    Fixes a string where UTF-8 characters were misinterpreted as Windows-1252.
    Returns 'cafe' in proper UTF-8 encoding.

.EXAMPLE
    Get-Content -Path 'C:\Logs\misencoded.txt' | ConvertFrom-MisencodedString

    Reads misencoded lines from a file and converts each line to the correct encoding.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.1
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+
    Permissions:   None required
    Module:        PSWinOps
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNull()]
        [AllowEmptyString()]
        [string]$String,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceEncoding = 'Cyrillic',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetEncoding = 'ASCII'
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting conversion - PowerShell $($PSVersionTable.PSVersion)"

        try {
            $sourceEncoder = [System.Text.Encoding]::GetEncoding($SourceEncoding)
            Write-Verbose "[$($MyInvocation.MyCommand)] Source encoding: $($sourceEncoder.EncodingName)"
        } catch {
            Write-Error "[$($MyInvocation.MyCommand)] Invalid source encoding '$SourceEncoding': $_"
            throw
        }

        try {
            $targetEncoder = [System.Text.Encoding]::GetEncoding($TargetEncoding)
            Write-Verbose "[$($MyInvocation.MyCommand)] Target encoding: $($targetEncoder.EncodingName)"
        } catch {
            Write-Error "[$($MyInvocation.MyCommand)] Invalid target encoding '$TargetEncoding': $_"
            throw
        }
    }

    process {
        # Handle empty strings without attempting conversion
        if ($String.Length -eq 0) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Empty string - returning unchanged"
            return ''
        }

        try {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing: '$String'"

            $bytes = $sourceEncoder.GetBytes($String)
            $result = $targetEncoder.GetString($bytes)

            Write-Verbose "[$($MyInvocation.MyCommand)] Converted successfully (Length: $($String.Length) --> $($result.Length))"

            $result
        } catch [System.Text.EncoderFallbackException] {
            Write-Error "[$($MyInvocation.MyCommand)] Encoding fallback error for '$String': $_"
            return
        } catch [System.ArgumentException] {
            Write-Error "[$($MyInvocation.MyCommand)] Invalid characters in string for encoding '$SourceEncoding': $_"
            return
        } catch {
            Write-Error "[$($MyInvocation.MyCommand)] Conversion failed for string '$String': $_"
            return
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
