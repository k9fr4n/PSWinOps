$Public  = Get-ChildItem -Path "$PSScriptRoot\Public"  -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue
$Private = Get-ChildItem -Path "$PSScriptRoot\Private" -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue

foreach ($file in @($Public + $Private)) {
    . $file.FullName
}

Export-ModuleMember -Function $Public.BaseName
