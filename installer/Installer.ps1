#requires -Version 5.1
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$AppName = 'RokuLAN Remote'
$Version = '__APP_VERSION__'
$AppFileName = 'RokuLANRemote.exe'
$ExpectedSha256 = '__APP_SHA256__'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\RokuLAN Remote'
$InstalledApp = Join-Path $InstallDir $AppFileName
$InstalledSetup = Join-Path $InstallDir 'RokuLANRemote-Package.exe'
$StartMenuLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RokuLAN Remote.lnk'
$DesktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RokuLAN Remote.lnk'
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RokuLANRemote'
$SetupPath = $env:RLR_SELF_EXE
$SetupCommandLine = $env:RLR_SELF_CMDLINE

function Show-Err([string]$m) { [void][System.Windows.Forms.MessageBox]::Show($m,$AppName,'OK','Error') }
function Show-Info([string]$m) { [void][System.Windows.Forms.MessageBox]::Show($m,$AppName,'OK','Information') }

function Get-EmbeddedAppBytes {
    if ([string]::IsNullOrWhiteSpace($SetupPath) -or -not (Test-Path -LiteralPath $SetupPath)) {
        throw 'Could not determine the setup executable path.'
    }
    $all = [IO.File]::ReadAllBytes($SetupPath)
    if ($all.Length -lt 24) { throw 'Setup payload is missing.' }
    $magic = [Text.Encoding]::ASCII.GetString($all, $all.Length - 24, 8)
    if ($magic -ne 'RLRPKG01') { throw 'Setup payload marker was not found.' }
    $appLen = [BitConverter]::ToInt64($all, $all.Length - 16)
    $scriptLen = [BitConverter]::ToInt64($all, $all.Length - 8)
    if ($appLen -le 0 -or $scriptLen -le 0 -or ($appLen + $scriptLen) -gt ($all.Length - 24)) { throw 'Setup payload length is invalid.' }
    $start = $all.Length - 24 - [int]$scriptLen - [int]$appLen
    $payload = New-Object byte[] ([int]$appLen)
    [Array]::Copy($all, $start, $payload, 0, [int]$appLen)
    $sha = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($payload)).Replace('-','').ToLowerInvariant()
    if ($sha -ne $ExpectedSha256.ToLowerInvariant()) { throw 'Embedded application failed SHA-256 verification.' }
    return $payload
}

function New-Link([string]$Path, [string]$Target) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($Path)
    $lnk.TargetPath = $Target
    $lnk.WorkingDirectory = Split-Path -Parent $Target
    $lnk.Description = 'Local-network desktop remote for Roku devices'
    $lnk.IconLocation = "$Target,0"
    $lnk.Save()
}

function Write-UninstallRegistration {
    if (-not (Test-Path $UninstallKey)) { New-Item -Path $UninstallKey -Force | Out-Null }
    New-ItemProperty -Path $UninstallKey -Name DisplayName -Value $AppName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name DisplayVersion -Value $Version -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name Publisher -Value 'RokuLAN Remote open-source project' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name InstallLocation -Value $InstallDir -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name DisplayIcon -Value $InstalledApp -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name UninstallString -Value ('"{0}" /uninstall' -f $InstalledSetup) -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name ModifyPath -Value ('"{0}" /repair' -f $InstalledSetup) -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name NoModify -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name NoRepair -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name EstimatedSize -Value 256 -PropertyType DWord -Force | Out-Null
}

function Install-App([bool]$DesktopShortcut) {
    $bytes = Get-EmbeddedAppBytes
    [IO.Directory]::CreateDirectory($InstallDir) | Out-Null
    $tmp = "$InstalledApp.new"
    [IO.File]::WriteAllBytes($tmp, $bytes)
    if (Test-Path -LiteralPath $InstalledApp) { Remove-Item -LiteralPath $InstalledApp -Force }
    Move-Item -LiteralPath $tmp -Destination $InstalledApp -Force
    $srcFull = [IO.Path]::GetFullPath($SetupPath)
    $dstFull = [IO.Path]::GetFullPath($InstalledSetup)
    if (-not $srcFull.Equals($dstFull, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.File]::WriteAllBytes($InstalledSetup, [IO.File]::ReadAllBytes($SetupPath))
    }
    New-Link $StartMenuLink $InstalledApp
    if ($DesktopShortcut) { New-Link $DesktopLink $InstalledApp }
    elseif (Test-Path -LiteralPath $DesktopLink) { Remove-Item -LiteralPath $DesktopLink -Force -ErrorAction SilentlyContinue }
    Write-UninstallRegistration
}

function Uninstall-App {
    Remove-Item -LiteralPath $StartMenuLink -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $DesktopLink -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $InstalledApp -Force -ErrorAction SilentlyContinue
    $escaped = $InstallDir.Replace('"','')
    Start-Process -FilePath 'cmd.exe' -ArgumentList ('/d /c ping 127.0.0.1 -n 3 >nul & rmdir /s /q "{0}"' -f $escaped) -WindowStyle Hidden
}

function Get-InstalledVersion {
    try { return (Get-ItemProperty -Path $UninstallKey -Name DisplayVersion -ErrorAction Stop).DisplayVersion }
    catch { return $null }
}

function Test-Arg([string]$name) {
    if ([string]::IsNullOrWhiteSpace($SetupCommandLine)) { return $false }
    return $SetupCommandLine -match ('(?i)(?:^|\s)[/-]' + [regex]::Escape($name) + '(?:\s|$)')
}

$quiet = Test-Arg 'quiet'
try {
    if (Test-Arg 'uninstall') {
        if (-not $quiet) {
            $r = [System.Windows.Forms.MessageBox]::Show('Remove RokuLAN Remote from this Windows account?',$AppName,'YesNo','Question')
            if ($r -ne 'Yes') { exit }
        }
        Uninstall-App
        if (-not $quiet) { Show-Info 'RokuLAN Remote was uninstalled.' }
        exit
    }
    if ((Test-Arg 'repair') -or (Test-Arg 'install') -or (Test-Arg 'update')) {
        $desktopWanted = if (Get-InstalledVersion) { Test-Path -LiteralPath $DesktopLink } else { $true }
        Install-App $desktopWanted
        if (-not $quiet) { Show-Info "RokuLAN Remote $Version is installed and repaired." }
        exit
    }
}
catch {
    if (-not $quiet) { Show-Err $_.Exception.Message }
    exit
}

$bg = [Drawing.Color]::FromArgb(24,25,30)
$panel = [Drawing.Color]::FromArgb(34,36,43)
$accent = [Drawing.Color]::FromArgb(121,73,205)
$text = [Drawing.Color]::FromArgb(236,238,243)
$muted = [Drawing.Color]::FromArgb(170,176,188)
$font = [Drawing.Font]::new('Segoe UI',10)
$bold = [Drawing.Font]::new('Segoe UI Semibold',10)
$titleFont = [Drawing.Font]::new('Segoe UI Semibold',16)
$form = New-Object Windows.Forms.Form
$form.Text = "$AppName Setup $Version"
$form.ClientSize = [Drawing.Size]::new(470,330)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = $bg
$form.ForeColor = $text
$form.Font = $font

$title = New-Object Windows.Forms.Label
$title.Text = 'RokuLAN Remote Setup'
$title.Font = $titleFont
$title.Location = [Drawing.Point]::new(22,20)
$title.Size = [Drawing.Size]::new(330,32)
$form.Controls.Add($title)

$installedVersion = Get-InstalledVersion
$status = New-Object Windows.Forms.Label
$status.ForeColor = $muted
$status.Location = [Drawing.Point]::new(24,62)
$status.Size = [Drawing.Size]::new(420,52)
if ($installedVersion) { $status.Text = "Installed: $installedVersion`r`nPackage: $Version" }
else { $status.Text = "Not currently installed.`r`nPackage: $Version" }
$form.Controls.Add($status)

$desktop = New-Object Windows.Forms.CheckBox
$desktop.Text = 'Create desktop shortcut'
$desktop.Checked = $true
$desktop.ForeColor = $text
$desktop.Location = [Drawing.Point]::new(24,122)
$desktop.Size = [Drawing.Size]::new(260,25)
$form.Controls.Add($desktop)

function Add-SetupButton([string]$label,[int]$x,[int]$y,[int]$w,[scriptblock]$click,[bool]$primary=$false) {
    $b=New-Object Windows.Forms.Button
    $b.Text=$label; $b.Location=[Drawing.Point]::new($x,$y); $b.Size=[Drawing.Size]::new($w,42)
    $b.FlatStyle='Flat'; $b.FlatAppearance.BorderSize=0; $b.Font=$bold
    $b.BackColor=$(if($primary){$accent}else{$panel}); $b.ForeColor=$text
    $b.Add_Click($click); $form.Controls.Add($b); return $b
}

$actionLabel = if (-not $installedVersion) { 'Install' } elseif ($installedVersion -ne $Version) { "Update to $Version" } else { 'Reinstall' }
$installBtn = Add-SetupButton $actionLabel 24 168 196 {
    try { Install-App $desktop.Checked; Show-Info "$AppName $Version is installed."; $form.Close() }
    catch { Show-Err $_.Exception.Message }
} $true
$repairBtn = Add-SetupButton 'Repair' 232 168 100 {
    try { Install-App $desktop.Checked; Show-Info 'Installation repaired.' }
    catch { Show-Err $_.Exception.Message }
}
$uninstallBtn = Add-SetupButton 'Uninstall' 344 168 100 {
    $r=[Windows.Forms.MessageBox]::Show('Remove RokuLAN Remote from this Windows account?',$AppName,'YesNo','Question')
    if($r -eq 'Yes'){ try { Uninstall-App; Show-Info 'RokuLAN Remote was uninstalled.'; $form.Close() } catch { Show-Err $_.Exception.Message } }
}
if (-not $installedVersion) { $repairBtn.Enabled=$false; $uninstallBtn.Enabled=$false }

$launchBtn = Add-SetupButton 'Launch RokuLAN Remote' 24 226 196 {
    if(Test-Path -LiteralPath $InstalledApp){ Start-Process -FilePath $InstalledApp }
} $false
$launchBtn.Enabled = [bool](Test-Path -LiteralPath $InstalledApp)
$closeBtn = Add-SetupButton 'Close' 344 226 100 { $form.Close() } $false

$note = New-Object Windows.Forms.Label
$note.Text = 'Per-user install • no administrator rights required • unsigned open-source build'
$note.ForeColor = $muted
$note.Location = [Drawing.Point]::new(24,286)
$note.Size = [Drawing.Size]::new(420,24)
$form.Controls.Add($note)

[void][Windows.Forms.Application]::Run($form)
