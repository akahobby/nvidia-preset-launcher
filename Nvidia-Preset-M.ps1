$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$launchedFromExplorer = $false
try {
    $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
    if ($pp -and $pp.ParentProcessId) {
        $parentProc = Get-Process -Id $pp.ParentProcessId -ErrorAction Stop
        if ($parentProc.Name -eq 'explorer') { $launchedFromExplorer = $true }
    }
} catch {}

try {
    $logPath = Join-Path $env:TEMP 'NvidiaProfileInspector.log'
    Start-Transcript -Path $logPath -Append | Out-Null
} catch {}

trap {
    try { Stop-Transcript | Out-Null } catch {}
    if ($launchedFromExplorer) {
        Write-Host "An error occurred. See log at: $logPath" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
        Read-Host "Press Enter to exit"
    }
    break
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $psExe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $psExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
try {
    $Host.UI.RawUI.WindowTitle = ($MyInvocation.MyCommand.Definition + " (Administrator)")
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.PrivateData.ProgressBackgroundColor = "Black"
    $Host.PrivateData.ProgressForegroundColor = "White"
    Clear-Host
} catch {}

$DocumentsRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Documents'
$InspectorDir  = Join-Path $DocumentsRoot 'NvidiaProfileInspector'
$InspectorExe  = Join-Path $InspectorDir 'Inspector.exe'
$InspectorURL  = 'https://github.com/FR33THYFR33THY/files/raw/main/Inspector.exe'
$TempNip       = Join-Path $env:TEMP 'nv_profile.nip'
$DrsPath       = 'C:\ProgramData\NVIDIA Corporation\Drs'

function Write-Info($msg){ Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg){ Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg){ Write-Host "[!] $msg" -ForegroundColor Yellow }

function Confirm-Inspector {
    if (-not (Test-Path $InspectorExe)) {
        Write-Info "Downloading Nvidia Profile Inspector to: $InspectorExe"
        New-Item -ItemType Directory -Path $InspectorDir -Force | Out-Null
        Invoke-WebRequest -Uri $InspectorURL -OutFile $InspectorExe
        Write-Ok "Downloaded Inspector.exe"
    } else {
        Write-Info "Using existing Inspector at $InspectorExe"
    }
}

function Unblock-Drs {
    if (Test-Path $DrsPath) {
        Write-Info "Unblocking DRS files..."
        Get-ChildItem -Path $DrsPath -Recurse -File -ErrorAction SilentlyContinue | Unblock-File
        Write-Ok "DRS unblocked"
    } else {
        Write-Warn "DRS path not found ($DrsPath). Skipping unblock."
    }
}

function Set-NipXml([string]$nipXml) {
    Set-Content -Path $TempNip -Value $nipXml -Encoding UTF8 -Force
    Write-Info "Importing profile via Inspector..."
    Start-Process -FilePath $InspectorExe -ArgumentList "`"$TempNip`"" -Wait
    Remove-Item $TempNip -Force -ErrorAction SilentlyContinue
    Write-Ok "Profile applied"
}

function Set-LegacySharpen([bool]$enable) {
    $value = if ($enable) { 0 } else { 1 }
    $keys = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\FTS',
        'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Parameters\FTS',
        'HKLM:\SYSTEM\ControlSet001\Services\nvlddmkm\Parameters\FTS'
    )
    foreach ($k in $keys) {
        if (Test-Path $k) {
            New-ItemProperty -Path $k -Name EnableGR535 -PropertyType DWord -Value $value -Force | Out-Null
        }
    }
    Write-Ok ("Legacy sharpen " + ($(if($enable){"ENABLED (0)"} else {"DISABLED (1)"})))
}

function Open-NvCpl {
    Write-Info "Opening NVIDIA Control Panel..."
    Start-Process "shell:appsFolder\NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel" | Out-Null
}

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

Confirm-Inspector
Unblock-Drs

Write-Host ""
Write-Host "1) NVIDIA Settings: On (Recommended)"
Write-Host "2) NVIDIA Settings: Default"
do {
    $choice = Read-Host "Select 1-2"
} until ($choice -match '^[1-2]$')

switch ($choice) {
    '1' {
        Set-NipXml -nipXml $Profile_On
        Set-LegacySharpen -enable:$true
        Open-NvCpl
    }
    '2' {
        Set-NipXml -nipXml $Profile_Default
        Set-LegacySharpen -enable:$false
        Open-NvCpl
    }
}

