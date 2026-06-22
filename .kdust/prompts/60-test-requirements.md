# TEST REQUIREMENTS

### Test file location
- `Public\<domain>\Verb-Noun.ps1` → `Tests\Public\<domain>\Verb-Noun.Tests.ps1`
- `Private\Verb-Noun.ps1` → `Tests\Private\Verb-Noun.Tests.ps1`

### Module import in BeforeAll
```
# For Tests\Public\<domain>\ (3 levels up to root)
BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

# For Tests\Private\ (2 levels up to root)
BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

# Calling a private function from tests
$result = & (Get-Module -Name 'PSWinOps') { Invoke-NativeCommand -Command 'hostname' }

# Mocking a private function from tests
Mock -CommandName 'Invoke-NativeCommand' -MockWith { } -ModuleName 'PSWinOps'
```

### Mandatory mocks by category

| Category | What to mock |
|---|---|
| Sessions | `quser.exe`/`query.exe`, `Invoke-Command`, `logoff.exe`, `mstsc.exe` |
| NTP | `w32tm.exe`, `Set-ItemProperty`, `Restart-Service` |
| Active Directory | `Get-ADUser`, `Get-ADComputer`, `Get-ADGroup`, `Get-ADDomain`, etc. |
| General | `Get-CimInstance`, `Invoke-CimMethod`, `Test-Connection` |

### Mandatory scenarios per function
- Happy path — local (`$env:COMPUTERNAME`)
- Happy path — explicit remote machine
- Pipeline — multiple machine names
- Per-machine failure — mock throws, function continues and writes error
- Parameter validation — empty/null/invalid triggers error

### Integration tests
Tag integration tests with `-Tag 'Integration'`.
Skip automatically when required binaries are absent:
```
It '...' -Skip:(-not (Test-Path "$env:SystemRoot\System32\qwinsta.exe")) { }
```
Exclude from CI pipeline in `build.ps1`:
```
$pesterConfig.Filter.ExcludeTag = @('Integration')
```
