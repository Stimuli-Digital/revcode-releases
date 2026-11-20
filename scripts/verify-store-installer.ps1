$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Run this installation/removal check only on a disposable GitHub Windows runner.'
}

$manifest = Get-Content (Join-Path $PSScriptRoot '../store-listing/en-US.json') -Raw | ConvertFrom-Json
$evidence = Join-Path $env:RUNNER_TEMP 'revcode-store-installer-verification'
New-Item -ItemType Directory -Force $evidence | Out-Null
$candidate = Join-Path $evidence 'candidate.msi'
$previous = Join-Path $evidence 'previous.msi'
$installedExe = Join-Path $env:ProgramFiles 'Revcode/gtm-pilot.exe'
$checks = [System.Collections.Generic.List[object]]::new()

function Get-RevcodeRegistration {
    @(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -eq 'Revcode' })
}

function Assert-SignedFile([string]$Path) {
    $signature = Get-AuthenticodeSignature $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Stimuli Digital LLC(?:,|$)' -or !$signature.TimeStamperCertificate) {
        throw "Invalid or unexpected timestamped publisher signature: $Path ($($signature.Status))"
    }
}

function Get-MsiProperty([string]$Path, [string]$Name) {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.OpenDatabase($Path, 0)
    $view = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$Name'")
    try {
        [void]$view.Execute()
        $record = $view.Fetch()
        if (!$record) { throw "Missing MSI property $Name" }
        $value = $record.StringData(1)
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)
        return $value
    } finally {
        [void]$view.Close()
        foreach ($item in @($view, $database, $installer)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item) }
    }
}

function Invoke-Msi([string]$Operation, [string]$Target, [string]$Label) {
    $log = Join-Path $evidence "$Label.log"
    $arguments = "$Operation `"$Target`" /quiet /norestart /L*v `"$log`""
    $process = Start-Process msiexec.exe -ArgumentList $arguments -PassThru
    if (!$process.WaitForExit(480000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Label timed out; see $log"
    }
    $process.Refresh()
    if ($process.ExitCode -notin @(0, 3010)) { throw "$Label failed with MSI exit code $($process.ExitCode); see $log" }
    $checks.Add(@{ check = $Label; exitCode = $process.ExitCode })
    Write-Host "$Label passed (exit $($process.ExitCode))"
}

function Assert-Installed([string]$Version, [string]$ProductCode) {
    $entries = @(Get-RevcodeRegistration)
    if ($entries.Count -ne 1 -or $entries[0].DisplayVersion -ne $Version -or $entries[0].PSChildName -ne $ProductCode) {
        throw "Expected exactly one Revcode $Version registration for $ProductCode."
    }
    if ($entries[0].Publisher -ne 'Stimuli Digital LLC') { throw 'Unexpected registered publisher.' }
    if (!(Test-Path $installedExe)) { throw 'Installed application executable is missing.' }
    Assert-SignedFile $installedExe
}

function Assert-Removed {
    if (@(Get-RevcodeRegistration).Count -ne 0 -or (Test-Path $installedExe)) {
        throw 'Revcode application registration or executable remains after removal.'
    }
}

if (@(Get-RevcodeRegistration).Count -ne 0 -or (Test-Path $installedExe)) {
    throw 'Runner is not clean; refusing to modify an existing installation.'
}

try {
    Invoke-WebRequest $manifest.package.installerUrl -OutFile $candidate -TimeoutSec 300
    if ((Get-FileHash $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.package.sha256) { throw 'Candidate checksum mismatch.' }
    Assert-SignedFile $candidate
    $candidateCode = Get-MsiProperty $candidate 'ProductCode'
    if ($candidateCode -ne $manifest.package.productCode -or (Get-MsiProperty $candidate 'ProductVersion') -ne $manifest.package.version) { throw 'Candidate MSI identity mismatch.' }

    Invoke-Msi '/i' $candidate 'fresh-install'
    Assert-Installed $manifest.package.version $candidateCode
    Invoke-Msi '/i' $candidate 'repeat-install'
    Assert-Installed $manifest.package.version $candidateCode
    Invoke-Msi '/x' $candidateCode 'fresh-install-removal'
    Assert-Removed

    # This older, already published signed MSI exercises migration across multiple releases.
    Invoke-WebRequest 'https://github.com/Stimuli-Digital/revcode-releases/releases/download/v0.62.5/Revcode_0.62.5_x64_en-US.msi' -OutFile $previous -TimeoutSec 300
    if ((Get-FileHash $previous -Algorithm SHA256).Hash.ToLowerInvariant() -ne '1307a371c4ba736ec49775238e981b4c5d244fd4bb7f19d6267aea20e18306c5') { throw 'Previous MSI checksum mismatch.' }
    Assert-SignedFile $previous
    $previousCode = Get-MsiProperty $previous 'ProductCode'
    Invoke-Msi '/i' $previous 'previous-version-install'
    Assert-Installed '0.62.5' $previousCode
    Invoke-Msi '/i' $candidate 'upgrade-from-0.62.5'
    Assert-Installed $manifest.package.version $candidateCode
    if (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$previousCode") { throw 'Previous MSI registration remains after upgrade.' }
    Invoke-Msi '/x' $candidateCode 'upgraded-install-removal'
    Assert-Removed
    $checks.Add(@{ check = 'registration-publisher-executable-and-removal'; result = 'passed' })
} finally {
    @{ version = $manifest.package.version; sha256 = $manifest.package.sha256; checks = @($checks.ToArray()) } |
        ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidence 'results.json')
}
