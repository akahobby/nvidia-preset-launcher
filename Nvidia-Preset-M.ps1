$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Paths = @{
    DocumentsRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Documents'
    TempNip       = Join-Path $env:TEMP 'nv_profile.nip'
    DrsPath       = 'C:\ProgramData\NVIDIA Corporation\Drs'
    LogPath       = Join-Path $env:TEMP 'NvidiaProfileInspector.log'
}
$Paths.InspectorDir = Join-Path $Paths.DocumentsRoot 'NvidiaProfileInspector'
$Paths.InspectorExe = Join-Path $Paths.InspectorDir 'Inspector.exe'

$NvControlPanelApp = 'shell:appsFolder\NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel'

function Write-Status([string]$Tag, [string]$Message, [string]$Color) {
    Write-Host "[$Tag] $Message" -ForegroundColor $Color
}

function Write-Info([string]$Message) { Write-Status -Tag '*'  -Message $Message -Color 'Cyan' }
function Write-Ok([string]$Message)   { Write-Status -Tag 'OK' -Message $Message -Color 'Green' }
function Write-Warn([string]$Message) { Write-Status -Tag '!'  -Message $Message -Color 'Yellow' }

function Test-LaunchedFromExplorer {
    try {
        $selfProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
        if (-not $selfProcess.ParentProcessId) { return $false }

        $parent = Get-Process -Id $selfProcess.ParentProcessId -ErrorAction Stop
        return ($parent.Name -eq 'explorer')
    } catch {
        return $false
    }
}

function Start-SessionTranscript {
    try {
        Start-Transcript -Path $Paths.LogPath -Append | Out-Null
    } catch {}
}

function Set-ConsoleTheme {
    try {
        $Host.UI.RawUI.WindowTitle = "$($MyInvocation.MyCommand.Definition) (Administrator)"
        $Host.UI.RawUI.BackgroundColor = 'Black'
        $Host.PrivateData.ProgressBackgroundColor = 'Black'
        $Host.PrivateData.ProgressForegroundColor = 'White'
        Clear-Host
    } catch {}
}

function Ensure-RunningAsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }

    $currentProcessPath = (Get-Process -Id $PID).Path
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath $currentProcessPath -Verb RunAs -ArgumentList $arguments
    exit
}

function Invoke-ReliableHttpGet {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$OutFile,
        [hashtable]$Headers = @{},
        [string]$UserAgent = 'nvidia-preset-launcher',
        [int]$Retries = 4
    )
    $ProgressPreference = 'SilentlyContinue'
    $last = $null
    for ($attempt = 0; $attempt -lt $Retries; $attempt++) {
        try {
            if ($OutFile) {
                Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 180 -Headers $Headers -UserAgent $UserAgent
                if (-not (Test-Path -LiteralPath $OutFile) -or (Get-Item -LiteralPath $OutFile).Length -lt 1) {
                    throw 'Downloaded file missing or empty'
                }
                return
            }
            return (Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 120 -Headers $Headers -UserAgent $UserAgent).Content
        } catch {
            $last = $_
            if ($OutFile) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue }
            if ($attempt -lt $Retries - 1) {
                Start-Sleep -Seconds ([Math]::Min(16, [Math]::Pow(2, $attempt)))
            }
        }
    }
    if ($OutFile) {
        $curl = Join-Path $env:WINDIR 'System32\curl.exe'
        if (Test-Path -LiteralPath $curl) {
            $curlArgs = [System.Collections.ArrayList]@('-fsSL', '-A', $UserAgent, '--connect-timeout', '30', '--max-time', '600', '--retry', '3', '--retry-delay', '2')
            foreach ($k in $Headers.Keys) {
                [void]$curlArgs.Add('-H')
                [void]$curlArgs.Add(('{0}: {1}' -f $k, $Headers[$k]))
            }
            [void]$curlArgs.Add('-o')
            [void]$curlArgs.Add($OutFile)
            [void]$curlArgs.Add($Uri)
            & $curl @($curlArgs.ToArray())
            if ((Test-Path -LiteralPath $OutFile) -and (Get-Item -LiteralPath $OutFile).Length -gt 0) { return }
        }
    }
    throw ("HTTP GET failed for {0}: {1}" -f $Uri, $last.Exception.Message)
}

function Get-LatestInspectorReleaseInfo {
    $uri = 'https://api.github.com/repos/Orbmu2k/nvidiaProfileInspector/releases?per_page=25'
    try {
        $json = Invoke-ReliableHttpGet -Uri $uri -Headers @{ Accept = 'application/vnd.github+json' }
        $releases = $json | ConvertFrom-Json
    } catch {
        throw "Could not query GitHub for Profile Inspector releases: $($_.Exception.Message)"
    }
    foreach ($rel in $releases) {
        if (-not $rel.assets) { continue }
        $assets = @($rel.assets)
        $asset = $assets | Where-Object { $_.name -ieq 'nvidiaProfileInspector.zip' } | Select-Object -First 1
        if (-not $asset) {
            $asset = $assets | Where-Object { $_.name -like '*.zip' -and $_.name -match 'profileinspector' } | Select-Object -First 1
        }
        if ($asset -and $asset.browser_download_url) {
            return [pscustomobject]@{
                DownloadUrl = [string]$asset.browser_download_url
                Tag         = [string]$rel.tag_name
            }
        }
    }
    throw 'No suitable .zip asset found in recent Orbmu2k/nvidiaProfileInspector GitHub releases.'
}

function Confirm-Inspector {
    $inspectorOk = $false
    if (Test-Path -LiteralPath $Paths.InspectorExe) {
        try {
            $fs = [System.IO.File]::OpenRead($Paths.InspectorExe)
            try {
                $buf = New-Object byte[] 2
                [void]$fs.Read($buf, 0, 2)
                if ($buf[0] -eq 0x4D -and $buf[1] -eq 0x5A) { $inspectorOk = $true }
            } finally { $fs.Dispose() }
        } catch {}
    }
    if ($inspectorOk) {
        Write-Info "Using existing Inspector at $($Paths.InspectorExe)"
        return
    }
    if (Test-Path -LiteralPath $Paths.InspectorExe) {
        Write-Warn 'Removing invalid Inspector.exe (wrong file or corrupt download).'
        Remove-Item -LiteralPath $Paths.InspectorExe -Force -ErrorAction SilentlyContinue
    }

    $release = Get-LatestInspectorReleaseInfo
    Write-Info ("Downloading latest Nvidia Profile Inspector ({0}) to: {1}" -f $release.Tag, $Paths.InspectorDir)
    New-Item -Path $Paths.InspectorDir -ItemType Directory -Force | Out-Null
    $zip = Join-Path $env:TEMP ('nvProfileInspector_{0}.zip' -f [Guid]::NewGuid().ToString('N'))
    $stage = Join-Path $env:TEMP ('nvProfileInspector_{0}' -f [Guid]::NewGuid().ToString('N'))
    try {
        Invoke-ReliableHttpGet -Uri $release.DownloadUrl -OutFile $zip
        Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
        $found = Get-ChildItem -Path $stage -Recurse -Filter 'nvidiaProfileInspector.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { throw 'nvidiaProfileInspector.exe not found in release zip.' }
        Copy-Item -LiteralPath $found.FullName -Destination $Paths.InspectorExe -Force
        Write-Ok ("Installed Inspector.exe from Orbmu2k release {0}" -f $release.Tag)
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Unblock-Drs {
    if (-not (Test-Path $Paths.DrsPath)) {
        Write-Warn "DRS path not found ($($Paths.DrsPath)). Skipping unblock."
        return
    }

    Write-Info 'Unblocking DRS files...'
    Get-ChildItem -Path $Paths.DrsPath -File -Recurse -ErrorAction SilentlyContinue | Unblock-File
    Write-Ok 'DRS unblocked'
}

function Set-NipXml([string]$NipXml) {
    Set-Content -Path $Paths.TempNip -Value $NipXml -Encoding Unicode -Force
    Write-Info 'Importing profile via Inspector...'
    Start-Process -FilePath $Paths.InspectorExe -ArgumentList "`"$($Paths.TempNip)`"" -Wait
    Remove-Item -Path $Paths.TempNip -Force -ErrorAction SilentlyContinue
    Write-Ok 'Profile applied'
}

function Set-LegacySharpen([bool]$Enable) {
    $registryValue = if ($Enable) { 0 } else { 1 }
    $registryTargets = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\FTS',
        'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Parameters\FTS',
        'HKLM:\SYSTEM\ControlSet001\Services\nvlddmkm\Parameters\FTS'
    )

    foreach ($target in $registryTargets) {
        if (-not (Test-Path $target)) { continue }

        New-ItemProperty -Path $target -Name EnableGR535 -PropertyType DWord -Value $registryValue -Force | Out-Null
    }

    $mode = if ($Enable) { 'ENABLED (0)' } else { 'DISABLED (1)' }
    Write-Ok "Legacy sharpen $mode"
}

function Open-NvCpl {
    Write-Info 'Opening NVIDIA Control Panel...'
    Start-Process $NvControlPanelApp | Out-Null
}

$launchedFromExplorer = Test-LaunchedFromExplorer
Start-SessionTranscript

trap {
    try { Stop-Transcript | Out-Null } catch {}
    if ($launchedFromExplorer) {
        Write-Host "An error occurred. See log at: $($Paths.LogPath)" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
        Read-Host 'Press Enter to exit'
    }
    break
}

Ensure-RunningAsAdministrator
Set-ConsoleTheme

$Profile_On = @'
<?xml version="1.0" encoding="utf-16"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName />
    <Executeables />
    <Settings>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>390467</SettingID>
        <SettingValue>2</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo />
        <SettingID>983226</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo />
        <SettingID>983227</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo />
        <SettingID>983295</SettingID>
        <SettingValue>AAAAQAAAAAA=</SettingValue>
        <ValueType>Binary</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Negative LOD bias</SettingNameInfo>
        <SettingID>1686376</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Trilinear optimization</SettingNameInfo>
        <SettingID>3066610</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync Tear Control</SettingNameInfo>
        <SettingID>5912412</SettingID>
        <SettingValue>2525368439</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred refresh rate</SettingNameInfo>
        <SettingID>6600001</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Maximum pre-rendered frames</SettingNameInfo>
        <SettingID>8102046</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Anisotropic filter optimization</SettingNameInfo>
        <SettingID>8703344</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync</SettingNameInfo>
        <SettingID>11041231</SettingID>
        <SettingValue>138504007</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Shader disk cache maximum size</SettingNameInfo>
        <SettingID>11306135</SettingID>
        <SettingValue>4294967295</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Quality</SettingNameInfo>
        <SettingID>13510289</SettingID>
        <SettingValue>20</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Anisotropic sample optimization</SettingNameInfo>
        <SettingID>15151633</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Display the VRR Indicator</SettingNameInfo>
        <SettingID>268604728</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Flag to control smooth AFR behavior</SettingNameInfo>
        <SettingID>270198627</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic filtering setting</SettingNameInfo>
        <SettingID>270426537</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Power management mode</SettingNameInfo>
        <SettingID>274197361</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Gamma correction</SettingNameInfo>
        <SettingID>276652957</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Mode</SettingNameInfo>
        <SettingID>276757595</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>FRL Low Latency</SettingNameInfo>
        <SettingID>277041152</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter</SettingNameInfo>
        <SettingID>277041154</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter for NVCPL</SettingNameInfo>
        <SettingID>277041162</SettingID>
        <SettingValue>357</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Toggle the VRR global feature</SettingNameInfo>
        <SettingID>278196567</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>VRR requested state</SettingNameInfo>
        <SettingID>278196727</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>G-SYNC</SettingNameInfo>
        <SettingID>279476687</SettingID>
        <SettingValue>4</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic filtering mode</SettingNameInfo>
        <SettingID>282245910</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Setting</SettingNameInfo>
        <SettingID>282555346</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Override DLSS-SR presets</SettingNameInfo>
        <SettingID>283385331</SettingID>
        <SettingValue>13</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Override DLSS-SR performance mode</SettingNameInfo>
        <SettingID>279951208</SettingID>
        <SettingValue>5</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable DLSS-SR override</SettingNameInfo>
        <SettingID>283385345</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>CUDA Sysmem Fallback Policy</SettingNameInfo>
        <SettingID>283962569</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable G-SYNC globally</SettingNameInfo>
        <SettingID>294973784</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>OpenGL GDI compatibility</SettingNameInfo>
        <SettingID>544392611</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Threaded optimization</SettingNameInfo>
        <SettingID>549528094</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred OpenGL GPU</SettingNameInfo>
        <SettingID>550564838</SettingID>
        <SettingValue>id,2.0:268410DE,00000100,GF - (400,2,161,24564) @ (0)</SettingValue>
        <ValueType>String</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vulkan/OpenGL present method</SettingNameInfo>
        <SettingID>550932728</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
</ArrayOfProfile>
'@
$Profile_Default = @'
<?xml version="1.0" encoding="utf-16"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>Base Profile</ProfileName>
    <Executeables />
    <Settings />
  </Profile>
</ArrayOfProfile>
'@

function Read-PresetSelection {
    Write-Host ''
    Write-Host '1) NVIDIA Settings: On (Recommended)'
    Write-Host '2) NVIDIA Settings: Default'

    do {
        $selection = Read-Host 'Select 1-2'
    } until ($selection -match '^[1-2]$')

    return $selection
}

function Invoke-PresetSelection([string]$Selection) {
    if ($Selection -eq '1') {
        Set-NipXml -NipXml $Profile_On
        Set-LegacySharpen -Enable:$true
    } else {
        Set-NipXml -NipXml $Profile_Default
        Set-LegacySharpen -Enable:$false
    }

    Open-NvCpl
}

Confirm-Inspector
Unblock-Drs

$selectedPreset = Read-PresetSelection
Invoke-PresetSelection -Selection $selectedPreset

