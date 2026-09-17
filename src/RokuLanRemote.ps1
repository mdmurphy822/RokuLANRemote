#requires -Version 5.1
<#
.SYNOPSIS
    RokuLAN Remote - a small Windows desktop remote for Roku devices on your LAN.

.DESCRIPTION
    Discovers Roku devices using SSDP and a local TCP/8060 fallback scan, then sends
    Roku External Control Protocol (ECP) commands over the local network.

    No telemetry. No cloud service. No credentials. Traffic stays on your LAN.

.NOTES
    Roku OS 14.1+ requires:
      Settings > System > Advanced system settings > Control by mobile apps
    to allow keypress/keydown/keyup ECP commands.

    Roku and related marks are trademarks of Roku, Inc. This project is not
    affiliated with or endorsed by Roku, Inc.
#>

Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Application state ----------
$script:AppName = 'RokuLAN Remote'
$script:Version = '0.2.0'
$script:Devices = @()
$script:SelectedDevice = $null
$script:StatusLabel = $null


# ---------- Helpers ----------
function Set-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ValidateSet('Normal','Good','Warn','Bad')][string]$Kind = 'Normal'
    )

    if ($null -eq $script:StatusLabel) { return }

    $script:StatusLabel.Text = $Text
    switch ($Kind) {
        'Good' { $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(125, 220, 160) }
        'Warn' { $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(245, 202, 95) }
        'Bad'  { $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(245, 120, 120) }
        default { $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(190, 195, 205) }
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Get-XmlValue {
    param(
        [Parameter(Mandatory = $true)]$Node,
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        $child = $Node.SelectSingleNode($Name)
        if ($null -ne $child) { return [string]$child.InnerText }
    }
    catch { }
    return $null
}

function Test-TruthyText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return @('1','true','yes','on') -contains $Value.Trim().ToLowerInvariant()
}


function Invoke-LanHttpGetString {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutMs = 2200
    )

    # Deliberately use the synchronous .NET WebRequest API here instead of
    # blocking on HttpClient async Tasks. In a WinForms PowerShell host,
    # sync-over-async can stall the UI message thread on some Windows/.NET
    # combinations. These calls are LAN-only, bounded by explicit timeouts,
    # and bypass the Windows system proxy for private-address requests.
    $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Url)
    $request.Method = 'GET'
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.Proxy = $null
    $request.KeepAlive = $false
    $request.AllowAutoRedirect = $false
    $request.UserAgent = "RokuLANRemote/$($script:Version)"

    $response = $null
    $stream = $null
    $reader = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $stream = $response.GetResponseStream()
        if ($null -eq $stream) { return '' }
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Invoke-LanHttpPostStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutMs = 2200
    )

    $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Url)
    $request.Method = 'POST'
    $request.ContentLength = 0
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.Proxy = $null
    $request.KeepAlive = $false
    $request.AllowAutoRedirect = $false
    $request.UserAgent = "RokuLANRemote/$($script:Version)"

    $response = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        return [int]$response.StatusCode
    }
    catch [System.Net.WebException] {
        if ($null -ne $_.Exception.Response) {
            $response = [System.Net.HttpWebResponse]$_.Exception.Response
            return [int]$response.StatusCode
        }
        throw
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Normalize-RokuBaseUrl {
    param([Parameter(Mandatory = $true)][string]$InputText)

    $raw = $InputText.Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    if ($raw -notmatch '^https?://') {
        $raw = "http://$raw"
    }

    try { $uri = [System.Uri]::new($raw) }
    catch { return $null }

    if ([string]::IsNullOrWhiteSpace($uri.Host)) { return $null }

    $port = $uri.Port
    if ($uri.IsDefaultPort -or $port -eq 80) { $port = 8060 }

    return "http://$($uri.Host):$port"
}

function Get-RokuDeviceInfo {
    param([Parameter(Mandatory = $true)][string]$BaseUrl)

    $base = $BaseUrl.TrimEnd('/')

    try {
        $xmlText = Invoke-LanHttpGetString "$base/query/device-info"
        [xml]$doc = $xmlText
        $root = $doc.DocumentElement
        if ($null -eq $root -or $root.Name -ne 'device-info') { return $null }

        $vendor = Get-XmlValue $root 'vendor-name'
        if ($vendor -and $vendor -notmatch '(?i)roku') { return $null }

        $friendly = Get-XmlValue $root 'user-device-name'
        if ([string]::IsNullOrWhiteSpace($friendly)) {
            $friendly = Get-XmlValue $root 'friendly-device-name'
        }

        # Some Roku models expose the friendliest name on the UPnP root document.
        if ([string]::IsNullOrWhiteSpace($friendly)) {
            try {
                $rootXmlText = Invoke-LanHttpGetString "$base/"
                [xml]$rootDoc = $rootXmlText
                $friendlyNode = $rootDoc.SelectSingleNode("//*[local-name()='friendlyName']")
                if ($null -ne $friendlyNode) { $friendly = [string]$friendlyNode.InnerText }
            }
            catch { }
        }

        $modelName = Get-XmlValue $root 'model-name'
        $modelNumber = Get-XmlValue $root 'model-number'
        $serial = Get-XmlValue $root 'serial-number'
        $software = Get-XmlValue $root 'software-version'
        $mode = Get-XmlValue $root 'ecp-setting-mode'
        $isTv = Test-TruthyText (Get-XmlValue $root 'is-tv')
        $supportsFindRemote = Test-TruthyText (Get-XmlValue $root 'supports-find-remote')
        $supportsAudio = Test-TruthyText (Get-XmlValue $root 'supports-audio-volume-control')
        $supportsTvPower = Test-TruthyText (Get-XmlValue $root 'supports-tv-power-control')

        $uri = [System.Uri]::new($base)
        $ip = $uri.Host

        if ([string]::IsNullOrWhiteSpace($friendly)) {
            if (-not [string]::IsNullOrWhiteSpace($modelName)) { $friendly = $modelName }
            elseif (-not [string]::IsNullOrWhiteSpace($modelNumber)) { $friendly = "Roku $modelNumber" }
            else { $friendly = "Roku $ip" }
        }

        $modelDisplay = @($modelName, $modelNumber) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $displayName = "$friendly  [$ip]"

        return [pscustomobject]@{
            FriendlyName = $friendly
            DisplayName = $displayName
            BaseUrl = $base
            IP = $ip
            ModelName = $modelName
            ModelNumber = $modelNumber
            ModelDisplay = ($modelDisplay -join ' / ')
            Serial = $serial
            SoftwareVersion = $software
            EcpMode = $mode
            IsTv = $isTv
            SupportsFindRemote = $supportsFindRemote
            SupportsAudio = ($supportsAudio -or $isTv)
            SupportsTvPower = ($supportsTvPower -or $isTv)
        }
    }
    catch {
        return $null
    }
}

# ---------- Discovery ----------
function Find-RokuViaSsdp {
    $results = New-Object System.Collections.Generic.List[string]
    $udp = $null

    try {
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Client.ReceiveTimeout = 250

        $destination = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse('239.255.255.250'), 1900)

        $request = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 1`r`nST: roku:ecp`r`n`r`n"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($request)
        [void]$udp.Send($bytes, $bytes.Length, $destination)

        $deadline = [DateTime]::UtcNow.AddSeconds(1.6)
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)

        while ([DateTime]::UtcNow -lt $deadline) {
            try {
                $responseBytes = $udp.Receive([ref]$remote)
                $response = [System.Text.Encoding]::ASCII.GetString($responseBytes)
                $match = [regex]::Match($response, '(?im)^location\s*:\s*(?<url>https?://[^\r\n]+)\s*$')
                if ($match.Success) {
                    $base = Normalize-RokuBaseUrl $match.Groups['url'].Value
                    if ($base -and -not $results.Contains($base)) {
                        $results.Add($base)
                    }
                }
            }
            catch [System.Net.Sockets.SocketException] {
                # Receive timeout. Keep polling until the overall deadline expires.
            }
            catch { }
        }
    }
    catch { }
    finally {
        if ($null -ne $udp) { $udp.Close() }
    }

    return @($results)
}

function Convert-IPv4ToUInt64 {
    param([Parameter(Mandatory = $true)][string]$IPAddress)
    $bytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    return ([uint64]$bytes[0] -shl 24) -bor ([uint64]$bytes[1] -shl 16) -bor ([uint64]$bytes[2] -shl 8) -bor [uint64]$bytes[3]
}

function Convert-UInt64ToIPv4 {
    param([Parameter(Mandatory = $true)][uint64]$Value)
    return ('{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255))
}

function Get-LocalScanTargets {
    $targetSet = New-Object 'System.Collections.Generic.HashSet[string]'

    try {
        $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.AddressState -eq 'Preferred' -and
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*'
            }
    }
    catch {
        $addresses = @()
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
                Where-Object {
                    $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                    $_.ToString() -notlike '127.*' -and
                    $_.ToString() -notlike '169.254.*'
                } |
                ForEach-Object {
                    [pscustomobject]@{ IPAddress = $_.ToString(); PrefixLength = 24 }
                }
        }
        catch { }
    }

    foreach ($entry in $addresses) {
        try {
            $ip = [string]$entry.IPAddress
            $prefix = [int]$entry.PrefixLength

            # Keep fallback discovery bounded. For very large LANs, scan the local /24.
            if ($prefix -lt 22 -or $prefix -gt 30) { $prefix = 24 }

            $ipNum = Convert-IPv4ToUInt64 $ip
            $blockSize = [uint64][math]::Pow(2, (32 - $prefix))
            $network = [uint64]([math]::Floor($ipNum / $blockSize) * $blockSize)
            $first = $network + 1
            $last = $network + $blockSize - 2

            for ($n = $first; $n -le $last; $n++) {
                $candidate = Convert-UInt64ToIPv4 $n
                if ($candidate -ne $ip) { [void]$targetSet.Add($candidate) }
            }
        }
        catch { }
    }

    return @($targetSet)
}

function Find-OpenRokuPorts {
    param([string[]]$Targets)

    if ($null -eq $Targets -or $Targets.Count -eq 0) { return @() }

    $pending = New-Object System.Collections.Generic.List[object]
    $open = New-Object System.Collections.Generic.List[string]

    foreach ($ip in $Targets) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $async = $client.BeginConnect($ip, 8060, $null, $null)
            $pending.Add([pscustomobject]@{
                IP = $ip
                Client = $client
                Async = $async
                Done = $false
            })
        }
        catch {
            $client.Close()
        }
    }

    $deadline = [DateTime]::UtcNow.AddMilliseconds(700)
    do {
        $unfinished = 0
        foreach ($item in $pending) {
            if ($item.Done) { continue }

            if ($item.Async.IsCompleted) {
                try {
                    $item.Client.EndConnect($item.Async)
                    if ($item.Client.Connected) { $open.Add($item.IP) }
                }
                catch { }
                finally {
                    $item.Client.Close()
                    $item.Done = $true
                }
            }
            else {
                $unfinished++
            }
        }

        if ($unfinished -gt 0) { Start-Sleep -Milliseconds 15 }
    } while ($unfinished -gt 0 -and [DateTime]::UtcNow -lt $deadline)

    foreach ($item in $pending) {
        if (-not $item.Done) {
            try { $item.Client.Close() } catch { }
            $item.Done = $true
        }
    }

    return @($open)
}

function Discover-RokuDevices {
    $candidates = New-Object 'System.Collections.Generic.HashSet[string]'

    Set-Status 'Discovering Roku devices via SSDP...' 'Normal'
    foreach ($base in (Find-RokuViaSsdp)) {
        if ($base) { [void]$candidates.Add($base) }
    }

    Set-Status 'Checking local network for port 8060...' 'Normal'
    $targets = Get-LocalScanTargets
    foreach ($ip in (Find-OpenRokuPorts $targets)) {
        [void]$candidates.Add("http://$ip`:8060")
    }

    $devices = New-Object System.Collections.Generic.List[object]
    foreach ($base in $candidates) {
        Set-Status "Verifying $base..." 'Normal'
        $device = Get-RokuDeviceInfo $base
        if ($null -ne $device) { $devices.Add($device) }
    }

    return @($devices | Sort-Object FriendlyName, IP)
}

# ---------- ECP commands ----------
function Get-SelectedRoku {
    if ($null -ne $script:SelectedDevice) { return $script:SelectedDevice }
    return $null
}

function Invoke-RokuPost {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string]$ActionLabel = 'Command',
        [switch]$Quiet
    )

    $device = Get-SelectedRoku
    if ($null -eq $device) {
        if (-not $Quiet) { Set-Status 'Select or connect to a Roku first.' 'Warn' }
        return $false
    }

    try {
        $url = "$($device.BaseUrl.TrimEnd('/'))/$RelativePath"
        $code = Invoke-LanHttpPostStatus $url

        if ($code -ge 200 -and $code -lt 300) {
            if (-not $Quiet) { Set-Status "$ActionLabel sent to $($device.FriendlyName)." 'Good' }
            return $true
        }

        if ($code -eq 403) {
            if (-not $Quiet) {
                Set-Status 'Roku returned 403. Set Control by mobile apps to Enabled/Permissive.' 'Bad'
            }
        }
        else {
            if (-not $Quiet) { Set-Status "Roku returned HTTP $code for $ActionLabel." 'Bad' }
        }

        return $false
    }
    catch {
        if (-not $Quiet) { Set-Status "Could not reach Roku: $($_.Exception.Message)" 'Bad' }
        return $false
    }
}

function Send-RokuKey {
    param([Parameter(Mandatory = $true)][string]$Key)
    [void](Invoke-RokuPost -RelativePath "keypress/$Key" -ActionLabel $Key)
}

function Send-RokuText {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        Set-Status 'Enter some text first.' 'Warn'
        return
    }

    $count = 0
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enumerator.MoveNext()) {
        $element = $enumerator.GetTextElement()
        $encoded = [System.Uri]::EscapeDataString($element)
        $ok = Invoke-RokuPost -RelativePath "keypress/Lit_$encoded" -ActionLabel 'Text' -Quiet
        if (-not $ok) {
            Set-Status 'Text entry stopped because the Roku rejected a command.' 'Bad'
            return
        }
        $count++
        Start-Sleep -Milliseconds 12
    }

    Set-Status "Sent $count character(s) to $($script:SelectedDevice.FriendlyName)." 'Good'
}

# ---------- UI ----------
$bg = [System.Drawing.Color]::FromArgb(24, 25, 30)
$panel = [System.Drawing.Color]::FromArgb(34, 36, 43)
$buttonBg = [System.Drawing.Color]::FromArgb(48, 51, 60)
$buttonHover = [System.Drawing.Color]::FromArgb(61, 65, 76)
$accent = [System.Drawing.Color]::FromArgb(121, 73, 205)
$text = [System.Drawing.Color]::FromArgb(236, 238, 243)
$muted = [System.Drawing.Color]::FromArgb(170, 176, 188)
$font = [System.Drawing.Font]::new('Segoe UI', 10)
$fontBold = [System.Drawing.Font]::new('Segoe UI Semibold', 10)
$titleFont = [System.Drawing.Font]::new('Segoe UI Semibold', 16)

$form = New-Object System.Windows.Forms.Form
$form.Text = "$($script:AppName) $($script:Version)"
$form.ClientSize = [System.Drawing.Size]::new(430, 710)
$form.MinimumSize = [System.Drawing.Size]::new(446, 749)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bg
$form.ForeColor = $text
$form.Font = $font
$form.KeyPreview = $true
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = 'RokuLAN Remote'
$title.Font = $titleFont
$title.ForeColor = $text
$title.Location = [System.Drawing.Point]::new(18, 14)
$title.Size = [System.Drawing.Size]::new(220, 30)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Local-network desktop remote'
$subtitle.ForeColor = $muted
$subtitle.Location = [System.Drawing.Point]::new(20, 43)
$subtitle.Size = [System.Drawing.Size]::new(260, 20)
$form.Controls.Add($subtitle)

$discoverButton = New-Object System.Windows.Forms.Button
$discoverButton.Text = 'Discover'
$discoverButton.Location = [System.Drawing.Point]::new(326, 18)
$discoverButton.Size = [System.Drawing.Size]::new(86, 34)
$discoverButton.FlatStyle = 'Flat'
$discoverButton.FlatAppearance.BorderSize = 0
$discoverButton.BackColor = $accent
$discoverButton.ForeColor = [System.Drawing.Color]::White
$discoverButton.Font = $fontBold
$form.Controls.Add($discoverButton)

$deviceCombo = New-Object System.Windows.Forms.ComboBox
$deviceCombo.DropDownStyle = 'DropDownList'
$deviceCombo.Location = [System.Drawing.Point]::new(20, 75)
$deviceCombo.Size = [System.Drawing.Size]::new(392, 30)
$deviceCombo.BackColor = $panel
$deviceCombo.ForeColor = $text
$deviceCombo.FlatStyle = 'Flat'
$form.Controls.Add($deviceCombo)

$deviceDetail = New-Object System.Windows.Forms.Label
$deviceDetail.Text = 'No Roku selected'
$deviceDetail.ForeColor = $muted
$deviceDetail.Location = [System.Drawing.Point]::new(20, 108)
$deviceDetail.Size = [System.Drawing.Size]::new(392, 38)
$form.Controls.Add($deviceDetail)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = 'Ready.'
$script:StatusLabel.ForeColor = $muted
$script:StatusLabel.Location = [System.Drawing.Point]::new(20, 147)
$script:StatusLabel.Size = [System.Drawing.Size]::new(392, 36)
$form.Controls.Add($script:StatusLabel)

function New-RemoteButton {
    param(
        [string]$Label,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [string]$Key,
        [switch]$AccentButton
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Label
    $button.Location = [System.Drawing.Point]::new($X, $Y)
    $button.Size = [System.Drawing.Size]::new($Width, $Height)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $(if ($AccentButton) { $accent } else { $buttonBg })
    $button.ForeColor = $text
    $button.Font = $fontBold
    $button.Tag = $Key
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Add_Click({
        param($sender, $eventArgs)
        Send-RokuKey ([string]$sender.Tag)
    })
    $form.Controls.Add($button)
    return $button
}

# Standard remote controls
$homeButton = New-RemoteButton 'Home' 20 190 190 40 'Home' -AccentButton
$backButton = New-RemoteButton 'Back' 220 190 92 40 'Back'
$infoButton = New-RemoteButton 'Info / *' 320 190 92 40 'Info'

$upButton = New-RemoteButton '▲' 170 242 90 48 'Up'
$leftButton = New-RemoteButton '◀' 70 296 90 48 'Left'
$selectButton = New-RemoteButton 'OK' 170 296 90 48 'Select' -AccentButton
$rightButton = New-RemoteButton '▶' 270 296 90 48 'Right'
$downButton = New-RemoteButton '▼' 170 350 90 48 'Down'

$replayButton = New-RemoteButton '↶ Replay' 20 414 92 40 'InstantReplay'
$revButton = New-RemoteButton '⏪' 120 414 74 40 'Rev'
$playButton = New-RemoteButton '▶ / ❚❚' 202 414 108 40 'Play'
$fwdButton = New-RemoteButton '⏩' 318 414 94 40 'Fwd'

$volumeDownButton = New-RemoteButton 'Vol −' 20 466 92 38 'VolumeDown'
$muteButton = New-RemoteButton 'Mute' 120 466 92 38 'VolumeMute'
$volumeUpButton = New-RemoteButton 'Vol +' 220 466 92 38 'VolumeUp'
$findRemoteButton = New-RemoteButton 'Find remote' 320 466 92 38 'FindRemote'

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = [System.Drawing.Point]::new(20, 523)
$textBox.Size = [System.Drawing.Size]::new(294, 28)
$textBox.BackColor = $panel
$textBox.ForeColor = $text
$textBox.BorderStyle = 'FixedSingle'
$form.Controls.Add($textBox)

$sendTextButton = New-Object System.Windows.Forms.Button
$sendTextButton.Text = 'Send text'
$sendTextButton.Location = [System.Drawing.Point]::new(322, 520)
$sendTextButton.Size = [System.Drawing.Size]::new(90, 34)
$sendTextButton.FlatStyle = 'Flat'
$sendTextButton.FlatAppearance.BorderSize = 0
$sendTextButton.BackColor = $buttonBg
$sendTextButton.ForeColor = $text
$sendTextButton.Font = $fontBold
$form.Controls.Add($sendTextButton)

$manualLabel = New-Object System.Windows.Forms.Label
$manualLabel.Text = 'Manual IP / host'
$manualLabel.ForeColor = $muted
$manualLabel.Location = [System.Drawing.Point]::new(20, 570)
$manualLabel.Size = [System.Drawing.Size]::new(145, 20)
$form.Controls.Add($manualLabel)

$manualBox = New-Object System.Windows.Forms.TextBox
$manualBox.Location = [System.Drawing.Point]::new(20, 592)
$manualBox.Size = [System.Drawing.Size]::new(294, 28)
$manualBox.BackColor = $panel
$manualBox.ForeColor = $text
$manualBox.BorderStyle = 'FixedSingle'
$manualBox.Text = ''
$form.Controls.Add($manualBox)

$connectButton = New-Object System.Windows.Forms.Button
$connectButton.Text = 'Connect'
$connectButton.Location = [System.Drawing.Point]::new(322, 589)
$connectButton.Size = [System.Drawing.Size]::new(90, 34)
$connectButton.FlatStyle = 'Flat'
$connectButton.FlatAppearance.BorderSize = 0
$connectButton.BackColor = $buttonBg
$connectButton.ForeColor = $text
$connectButton.Font = $fontBold
$form.Controls.Add($connectButton)

$shortcuts = New-Object System.Windows.Forms.Label
$shortcuts.Text = 'Keyboard: arrows • Enter=OK • Esc=Back • Space=Play/Pause • H=Home'
$shortcuts.ForeColor = $muted
$shortcuts.Location = [System.Drawing.Point]::new(20, 640)
$shortcuts.Size = [System.Drawing.Size]::new(392, 34)
$form.Controls.Add($shortcuts)

$privacy = New-Object System.Windows.Forms.Label
$privacy.Text = 'LAN only • SSDP + TCP/8060 discovery • no telemetry'
$privacy.ForeColor = [System.Drawing.Color]::FromArgb(125, 130, 142)
$privacy.Location = [System.Drawing.Point]::new(20, 675)
$privacy.Size = [System.Drawing.Size]::new(392, 22)
$form.Controls.Add($privacy)

function Update-SelectedDeviceUI {
    if ($null -eq $script:SelectedDevice) {
        $deviceDetail.Text = 'No Roku selected'
        $volumeDownButton.Enabled = $false
        $muteButton.Enabled = $false
        $volumeUpButton.Enabled = $false
        $findRemoteButton.Enabled = $false
        return
    }

    $d = $script:SelectedDevice
    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($d.ModelDisplay)) { $parts.Add($d.ModelDisplay) }
    if (-not [string]::IsNullOrWhiteSpace($d.SoftwareVersion)) { $parts.Add("OS $($d.SoftwareVersion)") }
    if (-not [string]::IsNullOrWhiteSpace($d.EcpMode)) { $parts.Add("ECP $($d.EcpMode)") }
    $deviceDetail.Text = $parts -join '  •  '

    $volumeDownButton.Enabled = $d.SupportsAudio
    $muteButton.Enabled = $d.SupportsAudio
    $volumeUpButton.Enabled = $d.SupportsAudio
    $findRemoteButton.Enabled = $d.SupportsFindRemote

    if ($d.EcpMode -and $d.EcpMode.ToLowerInvariant() -eq 'limited') {
        Set-Status 'Connected, but ECP is Limited. Remote keypresses may return 403.' 'Warn'
    }
    else {
        Set-Status "Connected to $($d.FriendlyName) at $($d.IP)." 'Good'
    }
}

function Load-DevicesIntoUI {
    param([object[]]$Devices)

    $script:Devices = @($Devices)
    $deviceCombo.Items.Clear()

    foreach ($device in $script:Devices) {
        [void]$deviceCombo.Items.Add($device.DisplayName)
    }

    if ($script:Devices.Count -gt 0) {
        $deviceCombo.SelectedIndex = 0
        $script:SelectedDevice = $script:Devices[0]
        Update-SelectedDeviceUI
        Set-Status "Found $($script:Devices.Count) Roku device(s)." 'Good'
    }
    else {
        $script:SelectedDevice = $null
        Update-SelectedDeviceUI
        Set-Status 'No Roku devices found. Try Manual IP / host.' 'Warn'
    }
}

function Start-Discovery {
    $discoverButton.Enabled = $false
    $deviceCombo.Enabled = $false
    try {
        $found = Discover-RokuDevices
        Load-DevicesIntoUI $found
    }
    finally {
        $discoverButton.Enabled = $true
        $deviceCombo.Enabled = $true
    }
}

$discoverButton.Add_Click({ Start-Discovery })

$deviceCombo.Add_SelectedIndexChanged({
    $index = $deviceCombo.SelectedIndex
    if ($index -ge 0 -and $index -lt $script:Devices.Count) {
        $script:SelectedDevice = $script:Devices[$index]
        Update-SelectedDeviceUI
    }
})

$sendTextButton.Add_Click({ Send-RokuText $textBox.Text })
$textBox.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Send-RokuText $textBox.Text
        $e.SuppressKeyPress = $true
    }
})

$connectButton.Add_Click({
    $base = Normalize-RokuBaseUrl $manualBox.Text
    if (-not $base) {
        Set-Status 'Enter an IP such as 192.168.1.100.' 'Warn'
        return
    }

    Set-Status "Connecting to $base..." 'Normal'
    $device = Get-RokuDeviceInfo $base
    if ($null -eq $device) {
        Set-Status "No Roku ECP service found at $base." 'Bad'
        return
    }

    $existingIndex = -1
    for ($i = 0; $i -lt $script:Devices.Count; $i++) {
        if ($script:Devices[$i].BaseUrl -eq $device.BaseUrl) {
            $existingIndex = $i
            break
        }
    }

    if ($existingIndex -lt 0) {
        $script:Devices += $device
        [void]$deviceCombo.Items.Add($device.DisplayName)
        $existingIndex = $script:Devices.Count - 1
    }
    else {
        $script:Devices[$existingIndex] = $device
        $deviceCombo.Items[$existingIndex] = $device.DisplayName
    }

    $deviceCombo.SelectedIndex = $existingIndex
    $script:SelectedDevice = $device
    Update-SelectedDeviceUI
})

$form.Add_KeyDown({
    param($sender, $e)

    if ($textBox.Focused -or $manualBox.Focused -or $deviceCombo.Focused) { return }

    $rokuKey = $null
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Up) { $rokuKey = 'Up' }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Down) { $rokuKey = 'Down' }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Left) { $rokuKey = 'Left' }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Right) { $rokuKey = 'Right' }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $rokuKey = 'Select' }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $rokuKey = 'Back' }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Space) { $rokuKey = 'Play' }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::H) { $rokuKey = 'Home' }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::I) { $rokuKey = 'Info' }

    if ($rokuKey) {
        Send-RokuKey $rokuKey
        $e.SuppressKeyPress = $true
        $e.Handled = $true
    }
})

$form.Add_FormClosed({ })

# Auto-discover shortly after the form becomes visible.
$startupTimer = New-Object System.Windows.Forms.Timer
$startupTimer.Interval = 250
$startupTimer.Add_Tick({
    $startupTimer.Stop()
    Start-Discovery
})

$form.Add_Shown({ $startupTimer.Start() })

Update-SelectedDeviceUI
[void][System.Windows.Forms.Application]::Run($form)
