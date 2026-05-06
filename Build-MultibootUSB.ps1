#Requires -Version 5.1
# Cross-platform: runs on Windows (PS 5.1+) and Linux/macOS (pwsh 7+)
<#
.SYNOPSIS
    Build-MultibootUSB.ps1 - Multiboot USB Builder with Ventoy.

.DESCRIPTION
    Builds a Ventoy multiboot USB with a curated ISO collection.
    - English / Spanish UI  (-Language en|es)
    - Fully customizable USB title  (-Title)
    - Interactive ISO selection menu with estimated disk usage
    - Dynamic version resolvers: always downloads latest stable
    - Multi-URL fallback per ISO, resumable cache
    - Disk space check before download
    - ventoy.json generated from selected ISOs only

.PARAMETER Language
    UI language: 'en' or 'es'. Prompted if omitted.

.PARAMETER Title
    Name for your multiboot USB (shown in Ventoy boot menu).

.PARAMETER DownloadDir
    Directory to cache ISOs before copying to USB.
    Default: %USERPROFILE%\<Title>_cache

.PARAMETER UsbDriveLetter
    (Windows) Drive letter of the Ventoy USB (e.g. F). Auto-detected if omitted.

.PARAMETER UsbMountPoint
    (Linux/macOS) Mount point of the Ventoy USB (e.g. /media/user/Ventoy). Auto-detected if omitted.

.PARAMETER UsbDevice
    (Linux/macOS) Block device for Ventoy install (e.g. /dev/sdb). Required if not using -SkipVentoyInstall.

.PARAMETER SkipPersistence
    Skip creating the Kali Linux persistence file.

.PARAMETER SkipVentoyInstall
    Skip downloading and running Ventoy2Disk.

.PARAMETER PersistenceSizeMB
    Size in MB for Kali persistence. Default: 8192.

.PARAMETER DirectToUSB
    Download ISOs straight to the USB (no cache, no copy step).
    Faster for one-shot builds. Mutually exclusive with -UseCache.

.PARAMETER UseCache
    Download ISOs to the cache directory first, then copy to the USB.
    Slower, but the cache can be re-used to build multiple USBs.
    Mutually exclusive with -DirectToUSB.

.EXAMPLE
    .\Build-MultibootUSB.ps1
    # Fully interactive (will ask for direct vs cache mode)

.EXAMPLE
    .\Build-MultibootUSB.ps1 -Language en -Title "MYLAB" -DirectToUSB -UsbDriveLetter F
    # Direct-to-USB, no cache

.EXAMPLE
    .\Build-MultibootUSB.ps1 -Language en -Title "MYLAB" -UseCache -DownloadDir "D:\isos" -UsbDriveLetter F
    # Cache mode, download to D:\isos and then copy
#>

[CmdletBinding()]
param(
    [ValidateSet('en','es')]
    [string]$Language,
    [string]$Title,
    [string]$DownloadDir,
    [string]$UsbDriveLetter,
    [string]$UsbMountPoint,
    [string]$UsbDevice,
    [switch]$SkipPersistence,
    [switch]$SkipVentoyInstall,
    [switch]$DirectToUSB,
    [switch]$UseCache,
    [int]$PersistenceSizeMB = 8192
)

if ($DirectToUSB -and $UseCache) {
    Write-Host "Cannot use both -DirectToUSB and -UseCache. Pick one." -ForegroundColor Red
    exit 1
}

# Cross-platform flags (PS5.1 on Windows doesn't define these — default to Windows)
$onLinux = $IsLinux  -eq $true
$onMac   = $IsMacOS  -eq $true
$onWin   = -not $onLinux -and -not $onMac

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12,
                                               [Net.SecurityProtocolType]::Tls13
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

# ============================================================================
# LOCALIZATION
# ============================================================================
$LANG = @{
    en = @{
        LangAsk        = 'Select language / Selecciona idioma [en/es, ENTER=en]: '
        TitleAsk       = 'Name for your multiboot USB  (e.g. MYBOOT, LABUSB, HACKDRIVE)'
        TitleRead      = '  Name [ENTER=MYBOOT]: '
        DirAsk         = 'Directory to cache ISO downloads  (~{0} GB recommended free)'
        DirRead        = '  Directory [ENTER={0}]: '
        DirFree        = 'Available: {0}'
        DirWarn        = 'WARNING: less than {0} GB free. You may run out of space.'
        IsoTitle       = 'SELECT ISOS TO DOWNLOAD'
        IsoHelp        = 'UP/DOWN navigate   SPACE toggle   A all   N none   ENTER confirm'
        IsoHelpAlt     = 'Type numbers to toggle (space-separated), A=all, N=none, ENTER=confirm: '
        IsoManual      = '(manual download)'
        IsoStats       = '{0} selected   ~{1} GB total'
        AdminErr       = 'Run as Administrator.'
        Step1          = '1/7  Resolving Ventoy'
        Step2          = '2/7  Locating Ventoy installer'
        Step3          = '3/7  Detecting Ventoy USB'
        Step4          = '4/7  Downloading ISOs'
        Step5          = '5/7  Downloading icons'
        Step6          = '6/7  Writing config files'
        Step7          = '7/7  Creating Kali persistence'
        StepIso        = '[{0}/{1}]  {2}'
        ManualMsg      = 'Manual download required (Microsoft). Place ISO in: {0}'
        SkippedMsg     = 'Skipped (not selected)'
        AlreadyCache   = 'Already cached ({0}). Skipping.'
        AlreadyUsb     = 'Already on USB. Skipping copy.'
        Copying        = 'Copying to USB...'
        Copied         = 'Copied'
        NoUsb          = 'No Ventoy USB found. Available volumes:'
        UsbPrompt      = 'Ventoy USB drive letter (or ENTER to abort): '
        UsbPromptLin   = 'Ventoy USB mount point (e.g. /media/user/Ventoy, or ENTER to abort): '
        UsbDevPrompt   = 'Block device for Ventoy (e.g. /dev/sdb, or ENTER to skip install): '
        UsbNoAccess    = 'Path {0} not found or not accessible.'
        VentoyOpen     = 'ENTER to open Ventoy2Disk  (CTRL+C if already installed)'
        VentoyOpenLin  = 'Block device to install Ventoy on (e.g. /dev/sdb, ENTER to skip): '
        VentoyMissing  = 'Ventoy installer not found. Download manually and rerun with -SkipVentoyInstall'
        VentoyFallback = 'GitHub API unreachable. Falling back to Ventoy v1.1.11'
        VentoyExtract  = 'Ventoy extracted'
        CacheOk        = 'Cache: {0}'
        CfgOk          = 'Config files written'
        PersistSkip    = 'Already exists. Skipping.'
        PersistOk      = 'Persistence file created'
        PersistSteps   = @(
            'After booting Kali with persistence, run in Kali terminal:',
            '  sudo mkfs.ext4 -L persistence /dev/disk/by-label/persistence',
            '  sudo mount -t ext4 /dev/disk/by-label/persistence /mnt',
            "  sudo bash -c 'echo / union > /mnt/persistence.conf'",
            '  sudo umount /mnt'
        )
        LtscNote       = 'Windows 11 IoT Enterprise LTSC cannot be auto-downloaded (Microsoft licensing). Get it from:'
        LtscUrl        = '  https://massgrave.dev/windows_ltsc_links  (official MSDN links aggregator)'
        LtscDest       = '  Then place the ISO in: {0}\ISO\Windows\'
        FidoGet        = 'Downloading Fido (Microsoft official ISO helper)...'
        FidoLaunch     = 'Fido will open  - select version, edition and language, then click Download'
        FidoBadUrl     = 'Fido did not return a valid URL'
        FidoOk         = 'Fido URL obtained. Downloading...'
        CustomLoaded   = '{0} custom ISO(s) loaded from custom-isos.json'
        CustomNone     = 'custom-isos.json not found - skipping custom ISOs'
        CustomInvalid  = 'custom-isos.json parse error: {0}'
        Summary        = 'SUMMARY'
        RetryTip       = 'To retry failed ISOs:'
        DoneMsg        = 'USB [{0}] ready at {1}'
        ManualWin      = 'Place Windows ISOs manually in {0}\ISO\Windows\ when ready'
        Resolving      = 'Resolving latest stable versions (this may take ~30s)...'
        PersistAsk     = 'Create Kali Linux persistence partition? [Y/N, ENTER=Y]: '
        PersistSzAsk   = 'Persistence size in MB  (e.g. 4096, 8192, 16384)'
        PersistSzRead  = '  Size MB [ENTER=8192]: '
        ModeAsk        = 'Download mode'
        ModeDirect     = '  [D] Direct to USB  (faster, no cache reuse, requires USB ready)'
        ModeCache      = '  [C] Cache + copy   (slower, cache reusable for other USBs)'
        ModePrompt     = '  Mode [D/c, ENTER=D]: '
        ModeDirectOk   = 'Mode: DIRECT to USB (downloads written straight to USB)'
        ModeCacheOk    = 'Mode: CACHE + COPY (downloads cached, then copied to USB)'
        DownloadingDirect = 'Downloading directly to USB...'
    }
    es = @{
        LangAsk        = 'Select language / Selecciona idioma [en/es, ENTER=en]: '
        TitleAsk       = 'Nombre para tu USB multiboot  (p.ej. MYBOOT, LABUSB, HACKDRIVE)'
        TitleRead      = '  Nombre [ENTER=MYBOOT]: '
        DirAsk         = 'Directorio para cachear las ISOs  (~{0} GB libres recomendados)'
        DirRead        = '  Directorio [ENTER={0}]: '
        DirFree        = 'Disponible: {0}'
        DirWarn        = 'AVISO: menos de {0} GB libres. Puede que te quedes sin espacio.'
        IsoTitle       = 'SELECCIONA LAS ISOS A DESCARGAR'
        IsoHelp        = 'ARRIBA/ABAJO navegar   ESPACIO activar   A todas   N ninguna   ENTER confirmar'
        IsoHelpAlt     = 'Numeros a activar/desactivar (separados por espacio), A=todas, N=ninguna, ENTER: '
        IsoManual      = '(descarga manual)'
        IsoStats       = '{0} seleccionadas   ~{1} GB total'
        AdminErr       = 'Ejecuta como Administrador.'
        Step1          = '1/7  Resolviendo Ventoy'
        Step2          = '2/7  Buscando instalador Ventoy'
        Step3          = '3/7  Detectando USB Ventoy'
        Step4          = '4/7  Descargando ISOs'
        Step5          = '5/7  Descargando iconos'
        Step6          = '6/7  Escribiendo ficheros de config'
        Step7          = '7/7  Creando persistencia Kali'
        StepIso        = '[{0}/{1}]  {2}'
        ManualMsg      = 'Requiere descarga manual (Microsoft). Pon la ISO en: {0}'
        SkippedMsg     = 'Omitida (no seleccionada)'
        AlreadyCache   = 'Ya en cache ({0}). Salto.'
        AlreadyUsb     = 'Ya en el USB. Salto copia.'
        Copying        = 'Copiando al USB...'
        Copied         = 'Copiado'
        NoUsb          = 'No detecto USB Ventoy. Volumenes disponibles:'
        UsbPrompt      = 'Letra del USB Ventoy (o ENTER para abortar): '
        UsbPromptLin   = 'Punto de montaje del USB Ventoy (ej. /media/user/Ventoy, o ENTER para abortar): '
        UsbDevPrompt   = 'Dispositivo de bloque para Ventoy (ej. /dev/sdb, o ENTER para saltar instalacion): '
        UsbNoAccess    = 'La ruta {0} no existe o no es accesible.'
        VentoyOpen     = 'ENTER para abrir Ventoy2Disk  (CTRL+C si ya esta instalado)'
        VentoyOpenLin  = 'Dispositivo donde instalar Ventoy (ej. /dev/sdb, ENTER para saltar): '
        VentoyMissing  = 'No encuentro el instalador Ventoy. Descargalo manualmente y relanza con -SkipVentoyInstall'
        VentoyFallback = 'GitHub API no responde. Usando Ventoy v1.1.11'
        VentoyExtract  = 'Ventoy descomprimido'
        CacheOk        = 'Cache: {0}'
        CfgOk          = 'Configs desplegadas'
        PersistSkip    = 'Ya existe. Salto.'
        PersistOk      = 'Persistencia creada'
        PersistSteps   = @(
            'Tras arrancar Kali con persistencia, ejecuta en terminal de Kali:',
            '  sudo mkfs.ext4 -L persistence /dev/disk/by-label/persistence',
            '  sudo mount -t ext4 /dev/disk/by-label/persistence /mnt',
            "  sudo bash -c 'echo / union > /mnt/persistence.conf'",
            '  sudo umount /mnt'
        )
        LtscNote       = 'Windows 11 IoT Enterprise LTSC no se puede descargar automaticamente (licencia Microsoft). Obtenla en:'
        LtscUrl        = '  https://massgrave.dev/windows_ltsc_links  (enlaces MSDN oficiales)'
        LtscDest       = '  Despues pon la ISO en: {0}\ISO\Windows\'
        FidoGet        = 'Descargando Fido (herramienta oficial de Microsoft para ISOs)...'
        FidoLaunch     = 'Se abrira Fido  - elige version, edicion e idioma y pulsa Download'
        FidoBadUrl     = 'Fido no devolvio una URL valida'
        FidoOk         = 'URL obtenida de Fido. Descargando...'
        CustomLoaded   = '{0} ISO(s) personalizadas cargadas desde custom-isos.json'
        CustomNone     = 'custom-isos.json no encontrado - omitiendo ISOs personalizadas'
        CustomInvalid  = 'Error al leer custom-isos.json: {0}'
        Summary        = 'RESUMEN'
        RetryTip       = 'Para reintentar las que fallaron:'
        DoneMsg        = 'USB [{0}] listo en {1}'
        ManualWin      = 'Pon las ISOs de Windows en {0}\ISO\Windows\ cuando las tengas'
        Resolving      = 'Resolviendo versiones estables actuales (~30s)...'
        PersistAsk     = '¿Crear particion de persistencia para Kali Linux? [S/N, ENTER=S]: '
        PersistSzAsk   = 'Tamaño de la persistencia en MB  (p.ej. 4096, 8192, 16384)'
        PersistSzRead  = '  Tamaño MB [ENTER=8192]: '
        ModeAsk        = 'Modo de descarga'
        ModeDirect     = '  [D] Directo al USB  (mas rapido, sin cache, requiere USB listo)'
        ModeCache      = '  [C] Cache + copia   (mas lento, cache reusable para otros USBs)'
        ModePrompt     = '  Modo [D/c, ENTER=D]: '
        ModeDirectOk   = 'Modo: DIRECTO al USB (las descargas van directamente al USB)'
        ModeCacheOk   = 'Modo: CACHE + COPIA (descarga al cache y luego copia al USB)'
        DownloadingDirect = 'Descargando directo al USB...'
    }
}
$L = $null  # set after language selection

# ============================================================================
# UI HELPERS
# ============================================================================
function Write-Step  ($m) { Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Write-Ok    ($m) { Write-Host "[OK] $m"  -ForegroundColor Green }
function Write-Warn2 ($m) { Write-Host "[!]  $m"  -ForegroundColor Yellow }
function Write-Err   ($m) { Write-Host "[X]  $m"  -ForegroundColor Red }
function Write-Info  ($m) { Write-Host "     $m"  -ForegroundColor DarkGray }

function Write-Banner {
    $line = '=' * 56
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Magenta
    Write-Host "   MULTIBOOT USB BUILDER  v2.0" -ForegroundColor Magenta
    if ($script:Title) {
        Write-Host ("   >> {0} <<" -f $script:Title.ToUpper()) -ForegroundColor White
    }
    Write-Host "  $line" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Config {
    Write-Host ("  USB Title:    {0}" -f $script:Title) -ForegroundColor DarkGray
    Write-Host ("  Cache:        {0}" -f $DownloadDir)  -ForegroundColor DarkGray
    Write-Host ("  USB:          {0}" -f $(if ($UsbDriveLetter) {"${UsbDriveLetter}:"} else {'(autodetect)'})) -ForegroundColor DarkGray
    Write-Host ("  Persistence:  {0}" -f $(if ($SkipPersistence) {'NO'} else {"$PersistenceSizeMB MB"})) -ForegroundColor DarkGray
    Write-Host ""
}

function Format-Bytes([long]$b) {
    $u = @('B','KB','MB','GB','TB'); $i = 0; $s = [double]$b
    while ($s -ge 1024 -and $i -lt 4) { $s /= 1024; $i++ }
    "{0:N2} {1}" -f $s, $u[$i]
}

function Test-Admin {
    if ($script:onLinux -or $script:onMac) {
        return ((id -u 2>/dev/null) -eq '0')
    }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DriveFreeGB([string]$path) {
    try {
        $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($path))
        $di   = New-Object System.IO.DriveInfo($root)
        return [Math]::Round($di.AvailableFreeSpace / 1GB, 1)
    } catch { return $null }
}

# ============================================================================
# DOWNLOAD ENGINE
# ============================================================================
function Invoke-DownloadMulti {
    param(
        [string[]]$Urls,
        [string]$OutFile,
        [int]$Retries   = 2,
        [long]$MinBytes = 5MB
    )

    if (Test-Path $OutFile) {
        $sz = (Get-Item $OutFile).Length
        if ($sz -gt $MinBytes) {
            $msg = if ($script:L) { $script:L.AlreadyCache -f (Format-Bytes $sz) } else { "Already cached ($(Format-Bytes $sz))." }
            Write-Info $msg
            return $true
        }
        Write-Info "Partial file found. Re-downloading."
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
    }

    foreach ($url in $Urls) {
        Write-Info "URL: $url"
        $tmp = "$OutFile.partial"
        for ($a = 1; $a -le $Retries; $a++) {
            try {
                Write-Info "Attempt $a/$Retries"
                try {
                    $head = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing `
                        -TimeoutSec 30 -MaximumRedirection 10 -ErrorAction Stop
                    if ($head.StatusCode -notin @(200,206)) {
                        Write-Warn2 "HEAD $($head.StatusCode). Trying next URL."; break
                    }
                } catch [System.Net.WebException] {
                    $sc = [int]$_.Exception.Response.StatusCode
                    if ($sc -in @(403,404,410)) { Write-Warn2 "HEAD $sc. Next URL."; break }
                    Write-Warn2 "HEAD error ($sc). Next URL."; break
                } catch {
                    Write-Warn2 "HEAD failed: $($_.Exception.Message). Next URL."; break
                }

                $got = $false
                if (Get-Module -ListAvailable -Name BitsTransfer) {
                    Import-Module BitsTransfer -ErrorAction SilentlyContinue
                    try {
                        Start-BitsTransfer -Source $url -Destination $tmp `
                            -DisplayName (Split-Path $OutFile -Leaf) -ErrorAction Stop
                        $got = $true
                    } catch {
                        Write-Info "BITS failed, switching to WebRequest..."
                        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                    }
                }
                if (-not $got) {
                    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
                }

                if ((Test-Path $tmp) -and (Get-Item $tmp).Length -gt $MinBytes) {
                    Move-Item $tmp $OutFile -Force
                    Write-Ok "Downloaded ($(Format-Bytes (Get-Item $OutFile).Length))"
                    return $true
                }
                Write-Warn2 "Download incomplete or empty."
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warn2 "Error: $($_.Exception.Message)"
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds (2 * $a)
            }
        }
    }
    Write-Err "All URLs failed."
    return $false
}

# ============================================================================
# DYNAMIC VERSION RESOLVERS
# ============================================================================
function Resolve-DebianUrls {
    param([string]$desktop = 'xfce', [string]$version = 'current')
    if ($version -in @('current','12','13')) {
        $base = 'https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/'
        try {
            $page = Invoke-WebRequest $base -UseBasicParsing -TimeoutSec 20
            $iso  = $page.Links | Where-Object { $_.href -match "debian-live-\d+\.\d+\.\d+-amd64-${desktop}\.iso`$" } |
                    Select-Object -Last 1
            if ($iso) { return @("$base$($iso.href)") }
        } catch {}
        return @(
            "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.1.0-amd64-${desktop}.iso",
            "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.0.0-amd64-${desktop}.iso"
        )
    }
    $known = @{ '12'='12.11.0'; '11'='11.11.0'; '10'='10.13.0' }
    $abase = 'https://cdimage.debian.org/cdimage/archive/'
    try {
        $page = Invoke-WebRequest $abase -UseBasicParsing -TimeoutSec 20
        $ver  = $page.Links | Where-Object { $_.href -match "^${version}\.\d+\.?\d*/$" } |
                ForEach-Object { $_.href.TrimEnd('/') } |
                Sort-Object { [version]$_ } | Select-Object -Last 1
        if ($ver) { return @("${abase}${ver}/amd64/iso-hybrid/debian-live-${ver}-amd64-${desktop}.iso") }
    } catch {}
    $fv = if ($known[$version]) { $known[$version] } else { "${version}.0" }
    return @("${abase}${fv}/amd64/iso-hybrid/debian-live-${fv}-amd64-${desktop}.iso")
}

function Resolve-UbuntuUrls {
    param([string]$flavor, [string]$version = '24.04')
    $codemap = @{ '20.04'='focal'; '22.04'='jammy'; '24.04'='noble'; '25.04'='plucky' }
    if (-not $codemap[$version]) { $version = '24.04' }
    $cn   = $codemap[$version]
    $base = "https://releases.ubuntu.com/$cn/"
    $vEsc = [regex]::Escape($version)
    try {
        $page = Invoke-WebRequest $base -UseBasicParsing -TimeoutSec 20
        $m    = $page.Links | Where-Object { $_.href -match "ubuntu-${vEsc}\.\d+-${flavor}-amd64\.iso$" } |
                Select-Object -First 1
        if ($m) { return @("$base$($m.href)") }
    } catch {}
    return @(
        "${base}ubuntu-${version}.6-${flavor}-amd64.iso",
        "${base}ubuntu-${version}.4-${flavor}-amd64.iso",
        "${base}ubuntu-${version}.3-${flavor}-amd64.iso",
        "${base}ubuntu-${version}.2-${flavor}-amd64.iso",
        "${base}ubuntu-${version}.1-${flavor}-amd64.iso",
        "${base}ubuntu-${version}-${flavor}-amd64.iso"
    )
}

function Resolve-UbuntuFlavorUrls {
    param([string]$slug, [string]$prefix, [string]$version, [string]$suffix = '-desktop-amd64.iso')
    $base = "https://cdimage.ubuntu.com/$slug/releases/$version/release/"
    $vEsc = [regex]::Escape($version)
    try {
        $page = Invoke-WebRequest $base -UseBasicParsing -TimeoutSec 20
        $iso  = $page.Links | Where-Object { $_.href -match "^${prefix}-${vEsc}(\.\d+)?${suffix}$" } |
                Select-Object -Last 1
        if ($iso) { return @("$base$($iso.href)") }
    } catch {}
    return @(
        "${base}${prefix}-${version}.2${suffix}",
        "${base}${prefix}-${version}.1${suffix}",
        "${base}${prefix}-${version}${suffix}"
    )
}

function Resolve-MintUrls {
    param([string]$edition = 'cinnamon')
    try {
        $base = 'https://mirrors.edge.kernel.org/linuxmint/stable/'
        $page = Invoke-WebRequest $base -UseBasicParsing -TimeoutSec 20
        $ver  = $page.Links | Where-Object { $_.href -match '^\d+\.\d+/$' } |
                ForEach-Object { $_.href.TrimEnd('/') } |
                Sort-Object { [version]$_ } | Select-Object -Last 1
        if ($ver) {
            $sub = Invoke-WebRequest "$base$ver/" -UseBasicParsing -TimeoutSec 20
            $iso = $sub.Links | Where-Object { $_.href -match "linuxmint-.*-${edition}-64bit\.iso$" } |
                   Select-Object -First 1
            if ($iso) {
                return @(
                    "${base}${ver}/$($iso.href)",
                    "https://mirror.karneval.cz/pub/linuxmint/iso/stable/$ver/$($iso.href)"
                )
            }
        }
    } catch {}
    return @(
        "https://mirrors.edge.kernel.org/linuxmint/stable/22.1/linuxmint-22.1-${edition}-64bit.iso",
        "https://mirrors.edge.kernel.org/linuxmint/stable/22/linuxmint-22-${edition}-64bit.iso",
        "https://mirror.karneval.cz/pub/linuxmint/iso/stable/22.1/linuxmint-22.1-${edition}-64bit.iso"
    )
}

function Resolve-ProxmoxUrls {
    try {
        $page   = Invoke-WebRequest 'https://download.proxmox.com/iso/' -UseBasicParsing -TimeoutSec 20
        $vtList = $page.Links | Where-Object { $_.href -match '^proxmox-ve_\d+\.\d+-\d+\.iso$' } |
                  ForEach-Object { $_.href } | Sort-Object -Descending
        if ($vtList) { return @("https://download.proxmox.com/iso/$($vtList[0])") }
    } catch {}
    return @(
        'https://download.proxmox.com/iso/proxmox-ve_8.4-1.iso',
        'https://download.proxmox.com/iso/proxmox-ve_8.3-1.iso'
    )
}

function Resolve-FedoraUrls {
    try {
        $page = Invoke-WebRequest 'https://dl.fedoraproject.org/pub/fedora/linux/releases/' `
                    -UseBasicParsing -TimeoutSec 20
        $ver  = $page.Links | Where-Object { $_.href -match '^\d+/$' } |
                ForEach-Object { [int]($_.href.TrimEnd('/')) } |
                Where-Object { $_ -gt 30 } | Sort-Object | Select-Object -Last 1
        if ($ver) {
            return @(
                "https://download.fedoraproject.org/pub/fedora/linux/releases/$ver/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-$ver-1.4.iso",
                "https://download.fedoraproject.org/pub/fedora/linux/releases/$ver/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-$ver-1.3.iso",
                "https://download.fedoraproject.org/pub/fedora/linux/releases/$ver/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-$ver-1.2.iso",
                "https://download.fedoraproject.org/pub/fedora/linux/releases/$ver/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-$ver-1.1.iso"
            )
        }
    } catch {}
    return @(
        'https://download.fedoraproject.org/pub/fedora/linux/releases/42/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-42-1.4.iso',
        'https://download.fedoraproject.org/pub/fedora/linux/releases/41/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-41-1.4.iso'
    )
}

function Resolve-EndeavourUrls {
    try {
        $page = Invoke-WebRequest 'https://mirror.alpix.eu/endeavouros/iso/' -UseBasicParsing -TimeoutSec 20
        $iso  = $page.Links | Where-Object { $_.href -match '^EndeavourOS_.*\.iso$' } | Select-Object -Last 1
        if ($iso) {
            return @(
                "https://mirror.alpix.eu/endeavouros/iso/$($iso.href)",
                "https://mirror.moson.org/endeavouros/iso/$($iso.href)",
                "https://mirrors.gigenet.com/endeavouros/iso/$($iso.href)"
            )
        }
    } catch {}
    return @(
        'https://mirror.alpix.eu/endeavouros/iso/EndeavourOS_Mercury-Neo-2025.03.19.iso',
        'https://mirror.moson.org/endeavouros/iso/EndeavourOS_Mercury-Neo-2025.03.19.iso',
        'https://mirrors.gigenet.com/endeavouros/iso/EndeavourOS_Mercury-Neo-2025.03.19.iso'
    )
}

function Resolve-KaliUrls {
    param([string]$variant)
    try {
        $page = Invoke-WebRequest 'https://cdimage.kali.org/current/' -UseBasicParsing -TimeoutSec 20
        $m    = $page.Links | Where-Object { $_.href -match "kali-linux-\d{4}\.\d+-${variant}\.iso$" } |
                Select-Object -First 1
        if ($m) { return @("https://cdimage.kali.org/current/$($m.href)") }
    } catch {}
    return @(
        "https://cdimage.kali.org/current/kali-linux-2025.4-${variant}.iso",
        "https://cdimage.kali.org/current/kali-linux-2025.3-${variant}.iso",
        "https://cdimage.kali.org/current/kali-linux-2025.2-${variant}.iso"
    )
}

function Resolve-ParrotUrls {
    try {
        $page = Invoke-WebRequest 'https://deb.parrot.sh/parrot/iso/' -UseBasicParsing -TimeoutSec 20
        $ver  = $page.Links | Where-Object { $_.href -match '^\d+\.\d+/?$' } |
                ForEach-Object { $_.href.TrimEnd('/') } |
                Sort-Object { [version]$_ } | Select-Object -Last 1
        if ($ver) {
            return @(
                "https://deb.parrot.sh/parrot/iso/$ver/Parrot-security-${ver}_amd64.iso",
                "https://deb.parrotsec.org/parrot/iso/$ver/Parrot-security-${ver}_amd64.iso"
            )
        }
    } catch {}
    return @(
        'https://deb.parrot.sh/parrot/iso/6.4/Parrot-security-6.4_amd64.iso',
        'https://deb.parrotsec.org/parrot/iso/6.4/Parrot-security-6.4_amd64.iso',
        'https://deb.parrot.sh/parrot/iso/6.3/Parrot-security-6.3_amd64.iso'
    )
}

function Resolve-ClonezillaUrls {
    try {
        $page = Invoke-WebRequest 'https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/' `
                    -UseBasicParsing -TimeoutSec 20
        $ver  = $page.Links | Where-Object { $_.href -match '/clonezilla_live_stable/[\d.-]+/$' } |
                ForEach-Object { ($_.href -split '/')[-2] } | Sort-Object | Select-Object -Last 1
        if ($ver) {
            return @(
                "https://downloads.sourceforge.net/clonezilla/clonezilla-live-${ver}-amd64.iso",
                "https://osdn.net/dl/clonezilla/clonezilla-live-${ver}-amd64.iso"
            )
        }
    } catch {}
    return @(
        'https://downloads.sourceforge.net/clonezilla/clonezilla-live-3.2.2-15-amd64.iso',
        'https://osdn.net/dl/clonezilla/clonezilla-live-3.2.2-15-amd64.iso'
    )
}

function Resolve-GpartedUrls {
    try {
        $page = Invoke-WebRequest 'https://sourceforge.net/projects/gparted/files/gparted-live-stable/' `
                    -UseBasicParsing -TimeoutSec 20
        $ver  = $page.Links | Where-Object { $_.href -match '/gparted-live-stable/[\d.-]+/$' } |
                ForEach-Object { ($_.href -split '/')[-2] } | Sort-Object | Select-Object -Last 1
        if ($ver) { return @("https://downloads.sourceforge.net/gparted/gparted-live-${ver}-amd64.iso") }
    } catch {}
    return @('https://downloads.sourceforge.net/gparted/gparted-live-1.6.0-3-amd64.iso')
}

function Resolve-SystemRescueUrls {
    try {
        $page = Invoke-WebRequest 'https://www.system-rescue.org/Download/' -UseBasicParsing -TimeoutSec 20
        if ($page.Content -match 'systemrescue-([\d.]+)-amd64\.iso') {
            $ver = $Matches[1]
            return @(
                "https://fastly-cdn.system-rescue.org/releases/$ver/systemrescue-$ver-amd64.iso",
                "https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/$ver/systemrescue-$ver-amd64.iso/download"
            )
        }
    } catch {}
    return @(
        'https://fastly-cdn.system-rescue.org/releases/11.03/systemrescue-11.03-amd64.iso',
        'https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/11.03/systemrescue-11.03-amd64.iso/download'
    )
}

function Resolve-FinnixUrls {
    try {
        $page = Invoke-WebRequest 'https://www.finnix.org/' -UseBasicParsing -TimeoutSec 20
        if ($page.Content -match 'finnix-(\d+)\.iso') {
            $ver = $Matches[1]
            return @("https://www.finnix.org/releases/current/finnix-$ver.iso")
        }
    } catch {}
    return @('https://www.finnix.org/releases/current/finnix-251.iso')
}

function Resolve-MemtestUrls {
    try {
        $page = Invoke-WebRequest 'https://www.memtest.org/' -UseBasicParsing -TimeoutSec 20
        if ($page.Content -match 'mt86plus_([\d.]+)\.iso\.zip') {
            $ver = $Matches[1]
            return @("https://www.memtest.org/download/v$ver/mt86plus_$ver.iso.zip")
        }
    } catch {}
    return @(
        'https://www.memtest.org/download/v7.20/mt86plus_7.20.iso.zip',
        'https://www.memtest.org/download/v7.00/mt86plus_7.00.iso.zip'
    )
}

function Resolve-ManjaroUrls {
    param([string]$desktop)  # kde, gnome, xfce
    try {
        $rel   = Invoke-RestMethod "https://api.github.com/repos/manjaro/$desktop/releases/latest" `
                     -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $asset = $rel.assets | Where-Object { $_.name -match '\.iso$' -and $_.name -notmatch '\.sha' } |
                 Select-Object -First 1
        if ($asset) { return @($asset.browser_download_url) }
    } catch {}
    return @("https://download.manjaro.org/$desktop/manjaro-$desktop-24.2.1-minimal.iso")
}

function Resolve-MxLinuxUrls {
    param([string]$edition = 'KDE')  # KDE, XFCE
    try {
        $page = Invoke-WebRequest "https://sourceforge.net/projects/mx-linux/files/Final/$edition/" `
                    -UseBasicParsing -TimeoutSec 20
        $iso  = $page.Links | Where-Object { $_.href -match "MX-[\d.]+_${edition}_x64\.iso$" } |
                Select-Object -Last 1
        if (-not $iso) { $iso = $page.Links | Where-Object { $_.href -match "MX-[\d.]+_x64\.iso$" } | Select-Object -Last 1 }
        if ($iso) {
            $name = ($iso.href -split '/')[-1]
            return @("https://downloads.sourceforge.net/project/mx-linux/Final/$edition/$name")
        }
    } catch {}
    return @("https://downloads.sourceforge.net/project/mx-linux/Final/$edition/MX-23.5_${edition}_x64.iso")
}

function Resolve-PopOsUrls {
    param([string]$version = '22.04', [string]$variant = 'intel')
    return @("https://iso.pop-os.org/$version/amd64/$variant/pop-os_${version}_amd64_$variant.iso")
}

function Resolve-OpenSuseUrls {
    param([string]$edition = 'leap')  # leap or tumbleweed
    if ($edition -eq 'tumbleweed') {
        return @(
            'https://download.opensuse.org/tumbleweed/iso/openSUSE-Tumbleweed-DVD-x86_64-Current.iso',
            'https://mirrors.kernel.org/opensuse/tumbleweed/iso/openSUSE-Tumbleweed-DVD-x86_64-Current.iso'
        )
    }
    try {
        $base = 'https://download.opensuse.org/distribution/leap/'
        $page = Invoke-WebRequest $base -UseBasicParsing -TimeoutSec 20
        $ver  = $page.Links | Where-Object { $_.href -match '^\d+\.\d+/?$' } |
                ForEach-Object { $_.href.TrimEnd('/') } | Sort-Object { [version]$_ } | Select-Object -Last 1
        if ($ver) {
            return @(
                "https://download.opensuse.org/distribution/leap/$ver/iso/openSUSE-Leap-$ver-DVD-x86_64.iso",
                "https://mirrors.kernel.org/opensuse/distribution/leap/$ver/iso/openSUSE-Leap-$ver-DVD-x86_64.iso"
            )
        }
    } catch {}
    return @(
        'https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-DVD-x86_64.iso',
        'https://mirrors.kernel.org/opensuse/distribution/leap/15.6/iso/openSUSE-Leap-15.6-DVD-x86_64.iso'
    )
}

function Resolve-TailsUrls {
    try {
        $page = Invoke-WebRequest 'https://mirrors.edge.kernel.org/tails/stable/' -UseBasicParsing -TimeoutSec 20
        $dir  = $page.Links | Where-Object { $_.href -match '^tails-amd64-[\d.]+/?$' } |
                ForEach-Object { $_.href.TrimEnd('/') } | Sort-Object | Select-Object -Last 1
        if ($dir) { return @("https://mirrors.edge.kernel.org/tails/stable/$dir/$dir.img") }
    } catch {}
    return @('https://mirrors.edge.kernel.org/tails/stable/tails-amd64-6.14/tails-amd64-6.14.img')
}

function Resolve-TrueNasUrls {
    try {
        $rel   = Invoke-RestMethod 'https://api.github.com/repos/truenas/truenas-installer/releases/latest' `
                     -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $asset = $rel.assets | Where-Object { $_.name -match '\.iso$' } | Select-Object -First 1
        if ($asset) { return @($asset.browser_download_url) }
    } catch {}
    return @('https://download.sys.truenas.com/TrueNAS-SCALE-ElectricEel-24.10.2/TrueNAS-SCALE-24.10.2.iso')
}

function Resolve-CentOsStreamUrls {
    param([string]$stream = '9')  # 9 or 10
    return @(
        "https://mirror.stream.centos.org/${stream}-stream/BaseOS/x86_64/iso/CentOS-Stream-${stream}-latest-x86_64-boot.iso",
        "https://ftp.plusline.net/centos-stream/${stream}-stream/BaseOS/x86_64/iso/CentOS-Stream-${stream}-latest-x86_64-boot.iso"
    )
}

# ============================================================================
# FIDO  - official Microsoft ISO download helper by Pete Batard (Rufus author)
# https://github.com/pbatard/Fido
# ============================================================================
function Invoke-FidoDownload {
    param([string]$OutFile, [hashtable]$Iso)

    $fidoPath = Join-Path $DownloadDir 'Fido.ps1'

    if (-not (Test-Path $fidoPath)) {
        Write-Info $script:L.FidoGet
        try {
            Invoke-WebRequest 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1' `
                -OutFile $fidoPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            Write-Ok "Fido.ps1"
        } catch {
            Write-Err "Cannot download Fido: $($_.Exception.Message)"
            return $false
        }
    }

    # Build argument list  - if all params are set, Fido runs headlessly
    $fidoArgs = @()
    if ($Iso.FidoWin)  { $fidoArgs += '-Win',  $Iso.FidoWin  }
    if ($Iso.FidoRel)  { $fidoArgs += '-Rel',  $Iso.FidoRel  }
    if ($Iso.FidoEd)   { $fidoArgs += '-Ed',   $Iso.FidoEd   }
    if ($Iso.FidoLang) { $fidoArgs += '-Lang', $Iso.FidoLang }
    if ($Iso.FidoArch) { $fidoArgs += '-Arch', $Iso.FidoArch }

    Write-Info $script:L.FidoLaunch
    try {
        $url = if ($fidoArgs.Count -gt 0) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fidoPath @fidoArgs
        } else {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fidoPath
        }

        # Fido may return multiple lines; grab the last https:// line
        $url = ($url | Where-Object { $_ -match '^https?://' } | Select-Object -Last 1)

        if (-not $url) {
            Write-Warn2 $script:L.FidoBadUrl
            return $false
        }

        Write-Ok $script:L.FidoOk
        Write-Info "URL: $url"
        return Invoke-DownloadMulti -Urls @($url.Trim()) -OutFile $OutFile
    } catch {
        Write-Err "Fido error: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# ISO CATALOG  (normalized output filenames; version is resolved in URLs)
# ============================================================================
function Get-IsoCatalog {
    return @(
        # ------------------------------------------------------------------ Debian 13 Trixie (current stable)  - all desktop environments
        @{ Folder='Linux\Debian'; Name='debian-13-live-amd64-xfce.iso';
           Alias='Debian 13 Trixie   - Xfce';        SizeMB=4000; Urls=(Resolve-DebianUrls 'xfce') }
        @{ Folder='Linux\Debian'; Name='debian-13-live-amd64-gnome.iso';
           Alias='Debian 13 Trixie   - GNOME';       SizeMB=4500; Urls=(Resolve-DebianUrls 'gnome') }
        @{ Folder='Linux\Debian'; Name='debian-13-live-amd64-kde.iso';
           Alias='Debian 13 Trixie   - KDE Plasma';  SizeMB=4500; Urls=(Resolve-DebianUrls 'kde') }
        @{ Folder='Linux\Debian'; Name='debian-13-live-amd64-cinnamon.iso';
           Alias='Debian 13 Trixie   - Cinnamon';    SizeMB=4000; Urls=(Resolve-DebianUrls 'cinnamon') }
        @{ Folder='Linux\Debian'; Name='debian-13-live-amd64-mate.iso';
           Alias='Debian 13 Trixie   - MATE';        SizeMB=4000; Urls=(Resolve-DebianUrls 'mate') }
        @{ Folder='Linux\Debian'; Name='debian-13-live-amd64-lxqt.iso';
           Alias='Debian 13 Trixie   - LXQt';        SizeMB=3500; Urls=(Resolve-DebianUrls 'lxqt') }
        @{ Folder='Linux\Debian'; Name='debian-13-live-amd64-lxde.iso';
           Alias='Debian 13 Trixie   - LXDE';        SizeMB=3000; Urls=(Resolve-DebianUrls 'lxde') }
        @{ Folder='Linux\Debian'; Name='debian-13-live-amd64-standard.iso';
           Alias='Debian 13 Trixie   - Standard (no DE)'; SizeMB=1500; Urls=(Resolve-DebianUrls 'standard') }

        # ------------------------------------------------------------------ Debian 12 Bookworm (archive)  - all desktop environments
        @{ Folder='Linux\Debian'; Name='debian-12-live-amd64-xfce.iso';
           Alias='Debian 12 Bookworm   - Xfce';      SizeMB=4000; Urls=(Resolve-DebianUrls 'xfce' '12') }
        @{ Folder='Linux\Debian'; Name='debian-12-live-amd64-gnome.iso';
           Alias='Debian 12 Bookworm   - GNOME';     SizeMB=4500; Urls=(Resolve-DebianUrls 'gnome' '12') }
        @{ Folder='Linux\Debian'; Name='debian-12-live-amd64-kde.iso';
           Alias='Debian 12 Bookworm   - KDE Plasma';SizeMB=4500; Urls=(Resolve-DebianUrls 'kde' '12') }
        @{ Folder='Linux\Debian'; Name='debian-12-live-amd64-cinnamon.iso';
           Alias='Debian 12 Bookworm   - Cinnamon';  SizeMB=4000; Urls=(Resolve-DebianUrls 'cinnamon' '12') }
        @{ Folder='Linux\Debian'; Name='debian-12-live-amd64-mate.iso';
           Alias='Debian 12 Bookworm   - MATE';      SizeMB=4000; Urls=(Resolve-DebianUrls 'mate' '12') }
        @{ Folder='Linux\Debian'; Name='debian-12-live-amd64-lxqt.iso';
           Alias='Debian 12 Bookworm   - LXQt';      SizeMB=3500; Urls=(Resolve-DebianUrls 'lxqt' '12') }
        @{ Folder='Linux\Debian'; Name='debian-12-live-amd64-lxde.iso';
           Alias='Debian 12 Bookworm   - LXDE';      SizeMB=3000; Urls=(Resolve-DebianUrls 'lxde' '12') }
        @{ Folder='Linux\Debian'; Name='debian-12-live-amd64-standard.iso';
           Alias='Debian 12 Bookworm   - Standard';  SizeMB=1500; Urls=(Resolve-DebianUrls 'standard' '12') }

        # ------------------------------------------------------------------ Debian 11 Bullseye (archive)  - key desktops
        @{ Folder='Linux\Debian'; Name='debian-11-live-amd64-xfce.iso';
           Alias='Debian 11 Bullseye   - Xfce';      SizeMB=3500; Urls=(Resolve-DebianUrls 'xfce' '11') }
        @{ Folder='Linux\Debian'; Name='debian-11-live-amd64-gnome.iso';
           Alias='Debian 11 Bullseye   - GNOME';     SizeMB=4000; Urls=(Resolve-DebianUrls 'gnome' '11') }
        @{ Folder='Linux\Debian'; Name='debian-11-live-amd64-kde.iso';
           Alias='Debian 11 Bullseye   - KDE Plasma';SizeMB=4000; Urls=(Resolve-DebianUrls 'kde' '11') }
        @{ Folder='Linux\Debian'; Name='debian-11-live-amd64-mate.iso';
           Alias='Debian 11 Bullseye   - MATE';      SizeMB=3500; Urls=(Resolve-DebianUrls 'mate' '11') }
        @{ Folder='Linux\Debian'; Name='debian-11-live-amd64-standard.iso';
           Alias='Debian 11 Bullseye   - Standard';  SizeMB=1200; Urls=(Resolve-DebianUrls 'standard' '11') }

        # ------------------------------------------------------------------ Ubuntu LTS  - Desktop + Server
        @{ Folder='Linux\Debian'; Name='ubuntu-24.04-desktop-amd64.iso';
           Alias='Ubuntu 24.04 LTS   - Desktop (GNOME)'; SizeMB=5000; Urls=(Resolve-UbuntuUrls 'desktop' '24.04') }
        @{ Folder='Linux\Debian'; Name='ubuntu-24.04-server-amd64.iso';
           Alias='Ubuntu 24.04 LTS   - Server';          SizeMB=2000; Urls=(Resolve-UbuntuUrls 'live-server' '24.04') }
        @{ Folder='Linux\Debian'; Name='ubuntu-22.04-desktop-amd64.iso';
           Alias='Ubuntu 22.04 LTS   - Desktop (GNOME)'; SizeMB=4500; Urls=(Resolve-UbuntuUrls 'desktop' '22.04') }
        @{ Folder='Linux\Debian'; Name='ubuntu-22.04-server-amd64.iso';
           Alias='Ubuntu 22.04 LTS   - Server';          SizeMB=1500; Urls=(Resolve-UbuntuUrls 'live-server' '22.04') }
        @{ Folder='Linux\Debian'; Name='ubuntu-20.04-desktop-amd64.iso';
           Alias='Ubuntu 20.04 LTS   - Desktop (GNOME)'; SizeMB=3000; Urls=(Resolve-UbuntuUrls 'desktop' '20.04') }
        @{ Folder='Linux\Debian'; Name='ubuntu-20.04-server-amd64.iso';
           Alias='Ubuntu 20.04 LTS   - Server';          SizeMB=1200; Urls=(Resolve-UbuntuUrls 'live-server' '20.04') }

        # ------------------------------------------------------------------ Kubuntu (KDE)
        @{ Folder='Linux\Debian'; Name='kubuntu-24.04-desktop-amd64.iso';
           Alias='Kubuntu 24.04 LTS   - KDE Plasma'; SizeMB=4500;
           Urls=(Resolve-UbuntuFlavorUrls 'kubuntu' 'kubuntu' '24.04') }
        @{ Folder='Linux\Debian'; Name='kubuntu-22.04-desktop-amd64.iso';
           Alias='Kubuntu 22.04 LTS   - KDE Plasma'; SizeMB=4000;
           Urls=(Resolve-UbuntuFlavorUrls 'kubuntu' 'kubuntu' '22.04') }
        @{ Folder='Linux\Debian'; Name='kubuntu-20.04-desktop-amd64.iso';
           Alias='Kubuntu 20.04 LTS   - KDE Plasma'; SizeMB=3000;
           Urls=(Resolve-UbuntuFlavorUrls 'kubuntu' 'kubuntu' '20.04') }

        # ------------------------------------------------------------------ Xubuntu (Xfce)
        @{ Folder='Linux\Debian'; Name='xubuntu-24.04-desktop-amd64.iso';
           Alias='Xubuntu 24.04 LTS   - Xfce';      SizeMB=3500;
           Urls=(Resolve-UbuntuFlavorUrls 'xubuntu' 'xubuntu' '24.04') }
        @{ Folder='Linux\Debian'; Name='xubuntu-22.04-desktop-amd64.iso';
           Alias='Xubuntu 22.04 LTS   - Xfce';      SizeMB=3000;
           Urls=(Resolve-UbuntuFlavorUrls 'xubuntu' 'xubuntu' '22.04') }
        @{ Folder='Linux\Debian'; Name='xubuntu-20.04-desktop-amd64.iso';
           Alias='Xubuntu 20.04 LTS   - Xfce';      SizeMB=2500;
           Urls=(Resolve-UbuntuFlavorUrls 'xubuntu' 'xubuntu' '20.04') }

        # ------------------------------------------------------------------ Lubuntu (LXQt)
        @{ Folder='Linux\Debian'; Name='lubuntu-24.04-desktop-amd64.iso';
           Alias='Lubuntu 24.04 LTS   - LXQt';      SizeMB=3000;
           Urls=(Resolve-UbuntuFlavorUrls 'lubuntu' 'lubuntu' '24.04') }
        @{ Folder='Linux\Debian'; Name='lubuntu-22.04-desktop-amd64.iso';
           Alias='Lubuntu 22.04 LTS   - LXQt';      SizeMB=2500;
           Urls=(Resolve-UbuntuFlavorUrls 'lubuntu' 'lubuntu' '22.04') }
        @{ Folder='Linux\Debian'; Name='lubuntu-20.04-desktop-amd64.iso';
           Alias='Lubuntu 20.04 LTS   - LXQt';      SizeMB=2000;
           Urls=(Resolve-UbuntuFlavorUrls 'lubuntu' 'lubuntu' '20.04') }

        # ------------------------------------------------------------------ Ubuntu MATE
        @{ Folder='Linux\Debian'; Name='ubuntu-mate-24.04-desktop-amd64.iso';
           Alias='Ubuntu MATE 24.04 LTS';           SizeMB=3500;
           Urls=(Resolve-UbuntuFlavorUrls 'ubuntu-mate' 'ubuntu-mate' '24.04') }
        @{ Folder='Linux\Debian'; Name='ubuntu-mate-22.04-desktop-amd64.iso';
           Alias='Ubuntu MATE 22.04 LTS';           SizeMB=3000;
           Urls=(Resolve-UbuntuFlavorUrls 'ubuntu-mate' 'ubuntu-mate' '22.04') }
        @{ Folder='Linux\Debian'; Name='ubuntu-mate-20.04-desktop-amd64.iso';
           Alias='Ubuntu MATE 20.04 LTS';           SizeMB=2500;
           Urls=(Resolve-UbuntuFlavorUrls 'ubuntu-mate' 'ubuntu-mate' '20.04') }

        # ------------------------------------------------------------------ Ubuntu Budgie
        @{ Folder='Linux\Debian'; Name='ubuntu-budgie-24.04-desktop-amd64.iso';
           Alias='Ubuntu Budgie 24.04 LTS';         SizeMB=4000;
           Urls=(Resolve-UbuntuFlavorUrls 'ubuntu-budgie' 'ubuntu-budgie' '24.04') }
        @{ Folder='Linux\Debian'; Name='ubuntu-budgie-22.04-desktop-amd64.iso';
           Alias='Ubuntu Budgie 22.04 LTS';         SizeMB=3500;
           Urls=(Resolve-UbuntuFlavorUrls 'ubuntu-budgie' 'ubuntu-budgie' '22.04') }

        # ------------------------------------------------------------------ Ubuntu Studio
        @{ Folder='Linux\Debian'; Name='ubuntustudio-24.04-dvd-amd64.iso';
           Alias='Ubuntu Studio 24.04 LTS';         SizeMB=4500;
           Urls=(Resolve-UbuntuFlavorUrls 'ubuntustudio' 'ubuntustudio' '24.04' '-dvd-amd64.iso') }
        @{ Folder='Linux\Debian'; Name='ubuntustudio-22.04-dvd-amd64.iso';
           Alias='Ubuntu Studio 22.04 LTS';         SizeMB=4000;
           Urls=(Resolve-UbuntuFlavorUrls 'ubuntustudio' 'ubuntustudio' '22.04' '-dvd-amd64.iso') }

        # ------------------------------------------------------------------ Linux Mint
        @{ Folder='Linux\Debian'; Name='linuxmint-cinnamon-64bit.iso';
           Alias='Linux Mint (latest)   - Cinnamon'; SizeMB=3000; Urls=(Resolve-MintUrls 'cinnamon') }
        @{ Folder='Linux\Debian'; Name='linuxmint-mate-64bit.iso';
           Alias='Linux Mint (latest)   - MATE';     SizeMB=2800; Urls=(Resolve-MintUrls 'mate') }
        @{ Folder='Linux\Debian'; Name='linuxmint-xfce-64bit.iso';
           Alias='Linux Mint (latest)   - Xfce';     SizeMB=2500; Urls=(Resolve-MintUrls 'xfce') }

        # ------------------------------------------------------------------ MX Linux
        @{ Folder='Linux\Debian'; Name='MX-latest-KDE_x64.iso';
           Alias='MX Linux (latest)   - KDE';        SizeMB=3000; Urls=(Resolve-MxLinuxUrls 'KDE') }
        @{ Folder='Linux\Debian'; Name='MX-latest-XFCE_x64.iso';
           Alias='MX Linux (latest)   - Xfce';       SizeMB=1500; Urls=(Resolve-MxLinuxUrls 'XFCE') }

        # ------------------------------------------------------------------ Pop!_OS
        @{ Folder='Linux\Debian'; Name='pop-os_22.04_amd64_intel.iso';
           Alias='Pop!_OS 22.04   - Intel/AMD';      SizeMB=2500; Urls=(Resolve-PopOsUrls '22.04' 'intel') }
        @{ Folder='Linux\Debian'; Name='pop-os_22.04_amd64_nvidia.iso';
           Alias='Pop!_OS 22.04   - NVIDIA';         SizeMB=2600; Urls=(Resolve-PopOsUrls '22.04' 'nvidia') }

        # ------------------------------------------------------------------ RHEL Family
        @{ Folder='Linux\RHEL'; Name='Rocky-9-latest-x86_64-minimal.iso';
           Alias='Rocky Linux 9   - Minimal';        SizeMB=1200
           Urls=@('https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-minimal.iso',
                  'https://mirror.23media.com/rockylinux/9/isos/x86_64/Rocky-9-latest-x86_64-minimal.iso') }
        @{ Folder='Linux\RHEL'; Name='Rocky-8-latest-x86_64-minimal.iso';
           Alias='Rocky Linux 8   - Minimal';        SizeMB=1200
           Urls=@('https://download.rockylinux.org/pub/rocky/8/isos/x86_64/Rocky-8-latest-x86_64-minimal.iso') }

        @{ Folder='Linux\RHEL'; Name='AlmaLinux-9-latest-x86_64-minimal.iso';
           Alias='AlmaLinux 9   - Minimal';          SizeMB=1200
           Urls=@('https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-minimal.iso') }
        @{ Folder='Linux\RHEL'; Name='AlmaLinux-8-latest-x86_64-minimal.iso';
           Alias='AlmaLinux 8   - Minimal';          SizeMB=1200
           Urls=@('https://repo.almalinux.org/almalinux/8/isos/x86_64/AlmaLinux-8-latest-x86_64-minimal.iso') }

        @{ Folder='Linux\RHEL'; Name='Fedora-Workstation-Live-x86_64.iso';
           Alias='Fedora Workstation (latest)';     SizeMB=2500; Urls=(Resolve-FedoraUrls) }

        @{ Folder='Linux\RHEL'; Name='CentOS-Stream-9-boot-x86_64.iso';
           Alias='CentOS Stream 9   - Boot';         SizeMB=800;  Urls=(Resolve-CentOsStreamUrls '9') }
        @{ Folder='Linux\RHEL'; Name='CentOS-Stream-10-boot-x86_64.iso';
           Alias='CentOS Stream 10   - Boot';        SizeMB=800;  Urls=(Resolve-CentOsStreamUrls '10') }

        @{ Folder='Linux\RHEL'; Name='OracleLinux-R9-x86_64-boot.iso';
           Alias='Oracle Linux 9   - Boot';          SizeMB=900
           Urls=@('https://yum.oracle.com/ISOS/OracleLinux/OL9/u5/x86_64/OracleLinux-R9-U5-x86_64-boot.iso',
                  'https://yum.oracle.com/ISOS/OracleLinux/OL9/u4/x86_64/OracleLinux-R9-U4-x86_64-boot.iso') }

        # ------------------------------------------------------------------ Arch Family
        @{ Folder='Linux\Arch'; Name='archlinux-x86_64.iso';
           Alias='Arch Linux (latest)';             SizeMB=1000
           Urls=@('https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso',
                  'https://mirrors.edge.kernel.org/archlinux/iso/latest/archlinux-x86_64.iso',
                  'https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso') }

        @{ Folder='Linux\Arch'; Name='EndeavourOS-latest.iso';
           Alias='EndeavourOS (latest)';            SizeMB=3000; Urls=(Resolve-EndeavourUrls) }

        @{ Folder='Linux\Arch'; Name='manjaro-kde-latest.iso';
           Alias='Manjaro   - KDE Plasma';           SizeMB=4000; Urls=(Resolve-ManjaroUrls 'kde') }
        @{ Folder='Linux\Arch'; Name='manjaro-gnome-latest.iso';
           Alias='Manjaro   - GNOME';                SizeMB=4000; Urls=(Resolve-ManjaroUrls 'gnome') }
        @{ Folder='Linux\Arch'; Name='manjaro-xfce-latest.iso';
           Alias='Manjaro   - Xfce';                 SizeMB=3500; Urls=(Resolve-ManjaroUrls 'xfce') }

        # ------------------------------------------------------------------ Other Linux
        @{ Folder='Linux\Other'; Name='openSUSE-Leap-latest-DVD-x86_64.iso';
           Alias='openSUSE Leap (latest)';          SizeMB=4500; Urls=(Resolve-OpenSuseUrls 'leap') }
        @{ Folder='Linux\Other'; Name='openSUSE-Tumbleweed-DVD-x86_64.iso';
           Alias='openSUSE Tumbleweed (rolling)';   SizeMB=4500; Urls=(Resolve-OpenSuseUrls 'tumbleweed') }

        # ------------------------------------------------------------------ Security / Privacy
        @{ Folder='Security'; Name='kali-linux-live-amd64.iso';
           Alias='Kali Linux Live (latest)';        SizeMB=4000; Urls=(Resolve-KaliUrls 'live-amd64') }
        @{ Folder='Security'; Name='kali-linux-installer-purple-amd64.iso';
           Alias='Kali Purple SOC (latest)';        SizeMB=4000; Urls=(Resolve-KaliUrls 'installer-purple-amd64') }
        @{ Folder='Security'; Name='Parrot-security-amd64.iso';
           Alias='Parrot Security OS (latest)';     SizeMB=3500; Urls=(Resolve-ParrotUrls) }
        @{ Folder='Security'; Name='tails-amd64.img';
           Alias='Tails (latest)   - privacy/anon';  SizeMB=1500; Urls=(Resolve-TailsUrls) }

        # ------------------------------------------------------------------ Sysadmin / Virtualisation
        @{ Folder='Sysadmin'; Name='proxmox-ve-latest.iso';
           Alias='Proxmox VE (latest)';             SizeMB=1200; Urls=(Resolve-ProxmoxUrls) }
        @{ Folder='Sysadmin'; Name='TrueNAS-SCALE-latest.iso';
           Alias='TrueNAS SCALE (latest)';          SizeMB=1500; Urls=(Resolve-TrueNasUrls) }
        @{ Folder='Sysadmin'; Name='clonezilla-live-amd64.iso';
           Alias='Clonezilla Live (latest)';        SizeMB=500;  Urls=(Resolve-ClonezillaUrls) }
        @{ Folder='Sysadmin'; Name='gparted-live-amd64.iso';
           Alias='GParted Live (latest)';           SizeMB=700;  Urls=(Resolve-GpartedUrls) }
        @{ Folder='Sysadmin'; Name='finnix-latest.iso';
           Alias='Finnix (latest)';                 SizeMB=500;  Urls=(Resolve-FinnixUrls) }

        # ------------------------------------------------------------------ Rescue
        @{ Folder='Rescue'; Name='systemrescue-amd64.iso';
           Alias='SystemRescue (latest)';           SizeMB=1000; Urls=(Resolve-SystemRescueUrls) }
        @{ Folder='Rescue'; Name='HBCD_PE_x64.iso';
           Alias="Hiren's BootCD PE";               SizeMB=2000
           Urls=@('https://www.hirensbootcd.org/files/HBCD_PE_x64.iso') }
        @{ Folder='Rescue'; Name='memtest86plus.iso';
           Alias='MemTest86+ (latest)';             SizeMB=15;   Urls=(Resolve-MemtestUrls); Unzip=$true }

        # ------------------------------------------------------------------ Windows
        @{ Folder='Windows'; Name='Win11_x64.iso';
           Alias='Windows 11  [Fido  - pick edition/lang]';  SizeMB=6000; Fido=$true
           FidoWin='11'; FidoArch='x64' }
        @{ Folder='Windows'; Name='Win11_IoT_Enterprise_LTSC_2024_x64.iso';
           Alias='Windows 11 IoT Enterprise LTSC 2024';     SizeMB=0; Manual=$true; ManualLtsc=$true
           Urls=@('https://massgrave.dev/windows_ltsc_links') }
        @{ Folder='Windows'; Name='Win10_x64.iso';
           Alias='Windows 10  [Fido  - pick edition/lang]';  SizeMB=5000; Fido=$true
           FidoWin='10'; FidoArch='x64' }
    )
}

# ============================================================================
# CUSTOM ISO LOADER   - reads custom-isos.json from script directory
# ============================================================================
function Get-CustomIsos {
    $jsonPath = Join-Path $PSScriptRoot 'custom-isos.json'
    if (-not (Test-Path $jsonPath)) {
        Write-Info $script:L.CustomNone
        return @()
    }
    try {
        $raw  = Get-Content $jsonPath -Raw -Encoding UTF8
        $list = $raw | ConvertFrom-Json
        $isos = @()
        foreach ($item in $list) {
            if (-not $item.Name -or -not $item.Urls) { continue }
            $isos += @{
                Folder  = if ($item.Folder)  { $item.Folder  } else { 'Custom' }
                Name    = $item.Name
                Alias   = if ($item.Alias)   { $item.Alias   } else { $item.Name }
                SizeMB  = if ($item.SizeMB)  { [int]$item.SizeMB } else { 0 }
                Urls    = @($item.Urls)
                Custom  = $true
            }
        }
        Write-Ok ($script:L.CustomLoaded -f $isos.Count)
        return $isos
    } catch {
        Write-Warn2 ($script:L.CustomInvalid -f $_.Exception.Message)
        return @()
    }
}

# ============================================================================
# ISO SELECTION MENU
# ============================================================================
function Show-IsoMenu {
    param([object[]]$Catalog)

    # ── Enable ANSI VT ────────────────────────────────────────────────────────
    $e = [char]27; $rst = "${e}[0m"
    try {
        if (-not ('IsoMenuVT.Kern' -as [type])) {
            Add-Type -Namespace IsoMenuVT -Name Kern -MemberDefinition @'
                [System.Runtime.InteropServices.DllImport("kernel32.dll")]
                public static extern System.IntPtr GetStdHandle(int h);
                [System.Runtime.InteropServices.DllImport("kernel32.dll")]
                public static extern bool GetConsoleMode(System.IntPtr h, out int m);
                [System.Runtime.InteropServices.DllImport("kernel32.dll")]
                public static extern bool SetConsoleMode(System.IntPtr h, int m);
'@
        }
        $hh = [IsoMenuVT.Kern]::GetStdHandle(-11)
        $mm = 0; [IsoMenuVT.Kern]::GetConsoleMode($hh,[ref]$mm)|Out-Null
        [IsoMenuVT.Kern]::SetConsoleMode($hh,$mm -bor 4)|Out-Null
    } catch {}

    # ── Space color palette ───────────────────────────────────────────────────
    $CY  = "${e}[38;5;51m"    # bright cyan
    $CYd = "${e}[38;5;38m"    # deep cyan
    $BL  = "${e}[38;5;39m"    # electric blue
    $GR  = "${e}[38;5;82m"    # bright green
    $YL  = "${e}[38;5;220m"   # yellow
    $OR  = "${e}[38;5;208m"   # orange
    $WH  = "${e}[38;5;231m"   # white
    $GY  = "${e}[38;5;246m"   # medium gray
    $DM  = "${e}[38;5;243m"   # dim gray
    $VD  = "${e}[38;5;240m"   # very dim
    $BO  = "${e}[1m"
    $BgCur = "${e}[48;5;17m"  # cursor bg dark navy
    $BgSec = "${e}[48;5;18m"  # section cursor bg
    $BOn = "${e}[38;5;39m"    # bar filled
    $BOff= "${e}[38;5;237m"   # bar empty

    # ── Symbols ───────────────────────────────────────────────────────────────
    $blk = [string][char]0x2588
    $lgt = [string][char]0x2591
    $chk = '*'; $arR = '>'; $arD = 'v'; $arL = '<'

    # ── Helpers ───────────────────────────────────────────────────────────────
    function vl([string]$s) { ($s -replace '\x1B\[[0-9;]*m','').Length }
    function wl([string]$a,[int]$W) {
        $pad = [Math]::Max(0,$W-(vl $a))
        $null = $script:_buf.Append($a + (' '*$pad) + $script:_rst + "`r`n")
    }
    function mkbar([int]$n,[int]$total,[int]$bw) {
        $f = if ($total-gt 0){[Math]::Min($bw,[Math]::Round($n*$bw/$total))}else{0}
        @{ v=($blk*$f)+($lgt*($bw-$f)); a=$BOn+($blk*$f)+$BOff+($lgt*($bw-$f))+$rst }
    }

    # ── Mutable catalog ───────────────────────────────────────────────────────
    $cat = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($iso in $Catalog) { $cat.Add($iso) }

    $recommended = @(
        'Debian 13 Trixie   - GNOME','Ubuntu 24.04 LTS   - Desktop (GNOME)',
        'Ubuntu 24.04 LTS   - Server','Rocky Linux 9   - Minimal',
        'Fedora Workstation (latest)','Arch Linux (latest)',
        'Kali Linux Live (latest)','Kali Purple SOC (latest)',
        'Parrot Security OS (latest)','Tails (latest)   - privacy/anon',
        'Proxmox VE (latest)','TrueNAS SCALE (latest)',
        'Clonezilla Live (latest)','GParted Live (latest)',
        'SystemRescue (latest)',"Hiren's BootCD PE",
        'MemTest86+ (latest)','Windows 11  [Fido  - pick edition/lang]'
    )

    $sel = [System.Collections.Generic.List[bool]]::new()
    for ($i=0;$i-lt $cat.Count;$i++) {
        $sel.Add(-not $cat[$i].Manual -and ($recommended -contains $cat[$i].Alias))
    }

    $interactive = $Host.Name -eq 'ConsoleHost'
    try { if ($interactive) { $null=$Host.UI.RawUI.WindowSize.Width } } catch { $interactive=$false }

    # ── Fallback text menu ────────────────────────────────────────────────────
    if (-not $interactive) {
        Write-Host ""; Write-Host ("  {0}" -f $script:L.IsoTitle) -ForegroundColor Cyan; Write-Host ""
        for ($i=0;$i-lt $cat.Count;$i++) {
            $iso=$cat[$i]; $check=if($iso.Manual){' - '}elseif($sel[$i]){'[*]'}else{'[ ]'}
            $sz=if($iso.SizeMB-gt 0){"  ~$([Math]::Round($iso.SizeMB/1024.0,1)) GB"}else{''}
            Write-Host ("  {0,2}  {1} {2}{3}" -f ($i+1),$check,$iso.Alias,$sz)
        }
        Write-Host ""
        while ($true) {
            $inp=(Read-Host ("  "+$script:L.IsoHelpAlt)).Trim()
            if ($inp-eq '') { break }
            if ($inp -in @('A','a')) { for($i=0;$i-lt $sel.Count;$i++){if(-not $cat[$i].Manual){$sel[$i]=$true}};break }
            if ($inp -in @('N','n')) { for($i=0;$i-lt $sel.Count;$i++){$sel[$i]=$false};break }
            foreach ($tok in ($inp -split '\s+')) {
                if ($tok -match '^\d+$') {
                    $idx=[int]$tok-1
                    if($idx-ge 0-and $idx-lt $cat.Count-and -not $cat[$idx].Manual){$sel[$idx]=-not $sel[$idx]}
                }
            }
        }
        return @{Sel=$sel.ToArray();Catalog=$cat.ToArray()}
    }

    # ── Section index ─────────────────────────────────────────────────────────
    $sectionOrder=[System.Collections.Generic.List[string]]::new()
    $sectionItems=@{}; $expanded=@{}
    for ($i=0;$i-lt $cat.Count;$i++) {
        $f=$cat[$i].Folder
        if (-not $sectionItems.ContainsKey($f)) {
            $sectionOrder.Add($f)
            $sectionItems[$f]=[System.Collections.Generic.List[int]]::new()
            $expanded[$f]=$false
        }
        $sectionItems[$f].Add($i)
    }

    $filterMode=$false; $filterText=''
    $packMode=$false; $packCursor=0

    $packDefs = @(
        @{Name='RESCUE';    USB=' 8-12 GB'; Desc='Rescue + repair essentials';                   ISOs=@("Hiren's BootCD PE",'GParted Live (latest)','SystemRescue (latest)','MemTest86+ (latest)','Clonezilla Live (latest)')}
        @{Name='FIELD OPS'; USB='   16 GB'; Desc='+ Debian minimal + Ubuntu Server + Kali';      ISOs=@("Hiren's BootCD PE",'GParted Live (latest)','SystemRescue (latest)','MemTest86+ (latest)','Clonezilla Live (latest)','Debian 12 Bookworm   - Standard (no DE)','Ubuntu 24.04 LTS   - Server','Kali Linux Live (latest)')}
        @{Name='SYSADMIN';  USB='   32 GB'; Desc='+ Desktop + Rocky + Proxmox + Win11';          ISOs=@("Hiren's BootCD PE",'GParted Live (latest)','SystemRescue (latest)','MemTest86+ (latest)','Clonezilla Live (latest)','Debian 13 Trixie   - GNOME','Ubuntu 24.04 LTS   - Desktop (GNOME)','Ubuntu 24.04 LTS   - Server','Rocky Linux 9   - Minimal','Proxmox VE (latest)','TrueNAS SCALE (latest)','Kali Linux Live (latest)','Windows 11  [Fido  - pick edition/lang]')}
        @{Name='DEVOPS';    USB='   64 GB'; Desc='+ Fedora + Arch + Parrot + Tails + Kali Purple';ISOs=@("Hiren's BootCD PE",'GParted Live (latest)','SystemRescue (latest)','MemTest86+ (latest)','Clonezilla Live (latest)','Debian 13 Trixie   - GNOME','Ubuntu 24.04 LTS   - Desktop (GNOME)','Ubuntu 24.04 LTS   - Server','Rocky Linux 9   - Minimal','Fedora Workstation (latest)','Arch Linux (latest)','Proxmox VE (latest)','TrueNAS SCALE (latest)','Kali Linux Live (latest)','Kali Purple SOC (latest)','Parrot Security OS (latest)','Tails (latest)   - privacy/anon','Windows 11  [Fido  - pick edition/lang]')}
        @{Name='ULTIMATE';  USB='  128 GB'; Desc='All major distros + security + tools';         ISOs=@("Hiren's BootCD PE",'GParted Live (latest)','SystemRescue (latest)','MemTest86+ (latest)','Clonezilla Live (latest)','Debian 13 Trixie   - GNOME','Debian 12 Bookworm   - GNOME','Ubuntu 24.04 LTS   - Desktop (GNOME)','Ubuntu 24.04 LTS   - Server','Ubuntu 22.04 LTS   - Desktop (GNOME)','Ubuntu 22.04 LTS   - Server','Rocky Linux 9   - Minimal','Fedora Workstation (latest)','Arch Linux (latest)','Proxmox VE (latest)','TrueNAS SCALE (latest)','Kali Linux Live (latest)','Kali Purple SOC (latest)','Parrot Security OS (latest)','Tails (latest)   - privacy/anon','Windows 11  [Fido  - pick edition/lang]','Windows 10  [Fido  - pick edition/lang]')}
        @{Name='CUSTOM';    USB='  any GB'; Desc='Manual selection';                              ISOs=@()}
    )

    $buildRows = {
        $r=[System.Collections.Generic.List[hashtable]]::new()
        if ($filterMode) {
            $ft=$filterText.ToLower()
            for ($i=0;$i-lt $cat.Count;$i++) {
                if ($cat[$i].Alias.ToLower().Contains($ft)-or $cat[$i].Folder.ToLower().Contains($ft)){
                    $r.Add(@{T='I';Idx=$i})
                }
            }
        } else {
            foreach ($f in $sectionOrder) {
                $items=$sectionItems[$f];$sc=0;$tmb=0
                foreach ($idx in $items){if($sel[$idx]){$sc++;$tmb+=$cat[$idx].SizeMB}}
                $r.Add(@{T='S';Folder=$f;Count=$items.Count;SelCount=$sc;TotalGB=[Math]::Round($tmb/1024.0,1);Exp=$expanded[$f]})
                if ($expanded[$f]){foreach ($idx in $items){$r.Add(@{T='I';Idx=$idx})}}
            }
        }
        ,$r
    }

    try { [Console]::Clear() } catch {}
    $cursor=0; $viewTop=0
    try { [Console]::CursorVisible=$false } catch {}

    try { while ($true) {

        $winH = [Math]::Max(14,[Console]::WindowHeight)
        $W    = [Math]::Min([Console]::WindowWidth, 90)

        # ── Pack selection overlay ────────────────────────────────────────────
        if ($packMode) {
            $script:_rst=$rst
            $script:_buf=[System.Text.StringBuilder]::new(4096)
            $null=$script:_buf.Append("${e}[H")
            $ptitle=" MULTIBOOT  /  USB  COMMANDER  "
            $pstA=" *  .    *  .  *    .  *    .  *  .    *  "; $pstB="  .    *  .  *    .  *    .  *  "
            $psp=$W-$ptitle.Length-$pstA.Length-$pstB.Length
            if($psp-lt 0){$pstB=$pstB.Substring(0,[Math]::Max(0,$pstB.Length+$psp))}
            wl "${VD}${pstA}${rst}${CY}${BO}${ptitle}${rst}${VD}${pstB}${rst}" $W
            wl "${BL}$('=' * $W)${rst}" $W
            wl "  ${CY}${BO}PRESET PACKS${rst}  ${DM}Select a configuration for your USB size   ENTER apply   ESC cancel${rst}" $W
            wl "${VD}$('-' * $W)${rst}" $W
            wl '' $W
            for ($pi=0;$pi-lt $packDefs.Count;$pi++) {
                $pd=$packDefs[$pi]
                $pMB=0; foreach ($al in $pd.ISOs){for($i2=0;$i2-lt $cat.Count;$i2++){if($cat[$i2].Alias-eq $al){$pMB+=$cat[$i2].SizeMB}}}
                $pGB=if($pMB-gt 0){"~$([Math]::Round($pMB/1024.0,0)) GB"}else{'---'}
                $nm=$pd.Name.PadRight(12); $usb=$pd.USB; $gb=$pGB.PadRight(10); $desc=$pd.Desc
                $cnt=if($pd.ISOs.Count-gt 0){"($($pd.ISOs.Count) ISOs)"}else{''}
                $ln=" ${nm}  ${usb}   ${gb}  ${desc}  ${DM}${cnt}"
                if($pi-eq $packCursor){ wl "  ${BgCur}${CY}${BO}>> ${ln}${rst}" $W }
                else                  { wl "     ${GY}${ln}${rst}" $W }
            }
            $pd2=$packDefs[$packCursor]
            wl '' $W
            if ($pd2.ISOs.Count -gt 0) {
                $previewLine="  ${DM}Includes: " + ($pd2.ISOs -join '  .  ') + "${rst}"
                $pvW=$W-4; if($previewLine.Length-gt $pvW){$previewLine=$previewLine.Substring(0,$pvW)+'>'}
                wl $previewLine $W
            }
            $linesDrawn=$packDefs.Count+7
            while($linesDrawn-lt ($winH-3)){wl '' $W;$linesDrawn++}
            wl "${VD}$('-' * $W)${rst}" $W
            wl "  ${BL}[up/down] navigate   [ENTER] apply pack   [ESC] cancel${rst}" $W
            wl "${BL}$('=' * $W)${rst}" $W
            [Console]::Write($script:_buf.ToString())
            $key=$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            switch ($key.VirtualKeyCode) {
                38 { if($packCursor-gt 0){$packCursor--} }
                40 { if($packCursor-lt($packDefs.Count-1)){$packCursor++} }
                27 { $packMode=$false }
                13 {
                    $pd=$packDefs[$packCursor]
                    for($i=0;$i-lt $sel.Count;$i++){$sel[$i]=$false}
                    if($pd.ISOs.Count-gt 0){
                        for($i=0;$i-lt $cat.Count;$i++){
                            if($pd.ISOs -contains $cat[$i].Alias){$sel[$i]=$true}
                        }
                    }
                    $packMode=$false
                }
            }
            continue
        }

        $rows  = & $buildRows
        $viewH = $winH - 8

        if ($cursor-ge $rows.Count){$cursor=[Math]::Max(0,$rows.Count-1)}
        if ($cursor-lt $viewTop)        {$viewTop=$cursor}
        if ($cursor-ge $viewTop+$viewH) {$viewTop=$cursor-$viewH+1}
        if ($viewTop-lt 0){$viewTop=0}

        $totalMB=0;$selCount=0
        for ($i=0;$i-lt $sel.Count;$i++){if($sel[$i]){$totalMB+=$cat[$i].SizeMB;$selCount++}}
        $totalGB=[Math]::Round($totalMB/1024.0,1)

        # ── Frame buffer ──────────────────────────────────────────────────────
        $script:_rst = $rst
        $script:_buf = [System.Text.StringBuilder]::new(8192)
        $null = $script:_buf.Append("${e}[H")

        # ── Header: star field + title ────────────────────────────────────────
        $title  = "  MULTIBOOT  /  USB  COMMANDER  "
        $starsA = " *  .    *  .  *    .  *    .  *  .    *  "
        $starsB = "  .    *  .  *    .  *    .  *  "
        $sp = $W - $title.Length - $starsA.Length - $starsB.Length
        if ($sp -lt 0) { $starsB=$starsB.Substring(0,[Math]::Max(0,$starsB.Length+$sp)) }
        wl "${VD}${starsA}${rst}${CY}${BO}${title}${rst}${VD}${starsB}${rst}" $W
        wl "${BL}$('=' * $W)${rst}" $W

        # Stats line
        $selPct=if($sel.Count-gt 0){[Math]::Min(100,[int]($selCount*100/$sel.Count))}else{0}
        $gb32=mkbar $selPct 100 32
        $sVis="  PAYLOAD  ${selCount} units  ~${totalGB} GB   $($gb32.v)   ${selPct}%  READY"
        $sAns="  ${YL}${BO}PAYLOAD${rst}  ${CY}${BO}${selCount}${rst} ${DM}units${rst}  ${OR}~${totalGB} GB${rst}   $($gb32.a)   ${WH}${selPct}%${rst}  ${GR}READY${rst}"
        wl $sAns $W
        wl "${VD}$('-' * $W)${rst}" $W

        # Context help
        $curRow=if($rows.Count-gt 0-and $cursor-lt $rows.Count){$rows[$cursor]}else{$null}
        if ($filterMode) {
            wl "  ${CY}[ SCAN: ${filterText}_ ]${rst}  ${DM}Type to filter   BKSP delete   ESC cancel   + beacon${rst}" $W
        } elseif ($curRow-and $curRow.T-eq 'S') {
            wl "  ${DM}ENTER open sector   SPC lock all   / scan   + beacon   A all   N none   F10 LAUNCH${rst}" $W
        } else {
            wl "  ${DM}SPC lock/unlock   ${arL} back   / scan   + beacon   A all   N none   F10 LAUNCH${rst}" $W
        }

        # ── Viewport ──────────────────────────────────────────────────────────
        $viewEnd=[Math]::Min($viewTop+$viewH-1,$rows.Count-1)
        $drawn=0

        if ($rows.Count-eq 0) {
            $msg=if($filterMode){"  ${YL}-- NO SIGNAL FOR '${filterText}' --   ${DM}Use + to add a custom beacon URL${rst}"}else{''}
            wl $msg $W; $drawn++
        }

        for ($r=$viewTop;$r-le $viewEnd;$r++) {
            $row=$rows[$r]
            $isCur=($r -eq $cursor)
            if ($row.T-eq 'S') {
                $b=mkbar $row.SelCount $row.Count 10
                $lockIcon=if($row.SelCount-eq $row.Count){"${GR}[${chk}]${rst}"}elseif($row.SelCount-eq 0){"${VD}[ ]${rst}"}else{"${YL}[-]${rst}"}
                $exp=if($row.Exp){$arD}else{$arR}
                $fPad=$row.Folder.PadRight(28)
                $sTxt=" $($row.SelCount)/$($row.Count)  ~$($row.TotalGB) GB"
                $visLen=4+3+28+$sTxt.Length+2+10
                $pad=' '*[Math]::Max(0,$W-$visLen)
                if ($isCur) {
                    $null=$script:_buf.Append("${BgSec}${WH}${BO} ${exp} ${lockIcon}${BgSec}${WH} ${fPad}${DM}${sTxt}  $($b.v)${pad}${rst}`r`n")
                } else {
                    $null=$script:_buf.Append("   ${lockIcon} ${BL}${exp}${rst} ${YL}${fPad}${rst}${DM}${sTxt}  $($b.a)${rst}${pad}`r`n")
                }
            } else {
                $i=$row.Idx; $iso=$cat[$i]
                if ($iso.Manual) {
                    $visL="       --  $($iso.Alias)"
                    $ansL="  ${VD}     --  $($iso.Alias)${rst}"
                } else {
                    $sym=if($sel[$i]){"${GR}[${chk}]${rst}"}else{"${DM}[ ]${rst}"}
                    $col=if($sel[$i]){$WH}else{$DM}
                    $sz=if($iso.SizeMB-gt 0){"  ~$([Math]::Round($iso.SizeMB/1024.0,1)) GB"}else{''}
                    $ctx=if($filterMode){" ${VD}[$($iso.Folder)]${rst}"}else{''}
                    $ctxV=if($filterMode){" [$($iso.Folder)]"}else{''}
                    $aW=$W-14-$sz.Length-$ctxV.Length
                    $aT=if($iso.Alias.Length-gt $aW){$iso.Alias.Substring(0,[Math]::Max(0,$aW-1))+'>'}else{$iso.Alias.PadRight($aW)}
                    $visL="      [.]  ${aT}${sz}${ctxV}"
                    $ansL="      ${sym}  ${col}${aT}${DM}${sz}${ctx}${rst}"
                }
                $pad=' '*[Math]::Max(0,$W-(vl $visL))
                if ($isCur) { $null=$script:_buf.Append("${BgCur}${CY}${BO}${visL}${pad}${rst}`r`n") }
                else        { $null=$script:_buf.Append($ansL+$pad+"`r`n") }
            }
            $drawn++
        }
        while ($drawn-lt $viewH) { $null=$script:_buf.Append((' '*$W)+"`r`n"); $drawn++ }

        # ── Footer ────────────────────────────────────────────────────────────
        wl "${VD}$('-' * $W)${rst}" $W
        if ($filterMode) {
            wl "  ${CY}[?] SCAN: type to filter   [BKSP] delete   [ESC] abort   [+] add beacon${rst}" $W
        } else {
            wl "  ${BL}[/] scan   [+] beacon   [P] packs   [SPC] lock   [ENTER] sector   [A/N] all/none   [F10] LAUNCH${rst}" $W
        }
        wl "${BL}$('=' * $W)${rst}" $W

        # ── Flush frame ───────────────────────────────────────────────────────
        [Console]::Write($script:_buf.ToString())

        # ── Input ─────────────────────────────────────────────────────────────
        $key=$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        # + beacon URL
        if ($key.Character -eq '+') {
            $inputY=[Console]::WindowHeight-5
            [Console]::SetCursorPosition(0,$inputY)
            try{[Console]::CursorVisible=$true}catch{}
            [Console]::Write("  ${CY}${BO}[+] BEACON URL (https://...):${rst}  ")
            $url=(Read-Host).Trim()
            if ($url -match '^https?://') {
                $fn=[System.IO.Path]::GetFileName(($url -split '[?#]')[0])
                $ext=[System.IO.Path]::GetExtension($fn).ToLower()
                $dType=switch($ext){'.iso'{'ISO image'};'.img'{'Disk image'};'.zip'{'ZIP archive'};default{"file ($ext)"}}
                $sizeMB=0
                try {
                    $resp=Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 8 -EA Stop
                    $cl=$resp.Headers['Content-Length']
                    if ($cl){$sizeMB=[Math]::Round([long]$cl/1MB,0)}
                    $ct=$resp.Headers['Content-Type']
                    if ($ct-and $ext -notin @('.iso','.img','.zip')){$dType=($ct -split ';')[0].Trim()}
                } catch {}
                [Console]::WriteLine("  ${GR}  SIGNAL: ${dType}   MASS: $(if($sizeMB){"~${sizeMB} MB"}else{'unknown'})${rst}")
                [Console]::Write("  ${CY}  CALLSIGN [${fn}]:${rst}  ")
                $name=(Read-Host).Trim()
                if ([string]::IsNullOrWhiteSpace($name)){$name=$fn}
                $newIso=@{Folder='Custom\Beacons';Name=$fn;Alias=$name;SizeMB=$sizeMB;Urls=@($url);Custom=$true}
                $cat.Add($newIso); $sel.Add($true)
                $f='Custom\Beacons'
                if (-not $sectionItems.ContainsKey($f)){
                    $sectionOrder.Add($f)
                    $sectionItems[$f]=[System.Collections.Generic.List[int]]::new()
                    $expanded[$f]=$true
                }
                $sectionItems[$f].Add($cat.Count-1)
            }
            try{[Console]::CursorVisible=$false}catch{}
            try{[Console]::Clear()}catch{}
            continue
        }

        # Filter mode
        if ($filterMode) {
            switch ($key.VirtualKeyCode) {
                27  { $filterMode=$false;$filterText='';$cursor=0;$viewTop=0 }
                8   { if($filterText.Length-gt 0){$filterText=$filterText.Substring(0,$filterText.Length-1);$cursor=0;$viewTop=0} }
                38  { $p=$cursor-1;while($p-ge 0-and $rows[$p].T-eq 'I'-and $cat[$rows[$p].Idx].Manual){$p--};if($p-ge 0){$cursor=$p} }
                40  { $n=$cursor+1;while($n-lt $rows.Count-and $rows[$n].T-eq 'I'-and $cat[$rows[$n].Idx].Manual){$n++};if($n-lt $rows.Count){$cursor=$n} }
                32  { if($cursor-lt $rows.Count-and $rows[$cursor].T-eq 'I'){$i2=$rows[$cursor].Idx;if(-not $cat[$i2].Manual){$sel[$i2]=-not $sel[$i2]}} }
                13  { [Console]::WriteLine('');return @{Sel=$sel.ToArray();Catalog=$cat.ToArray()} }
                121 { [Console]::WriteLine('');return @{Sel=$sel.ToArray();Catalog=$cat.ToArray()} }
                default { $ch=$key.Character;if($ch-ge ' '-and $ch-ne [char]0){$filterText+=$ch;$cursor=0;$viewTop=0} }
            }
            continue
        }

        # Normal mode
        $curRow=if($rows.Count-gt 0-and $cursor-lt $rows.Count){$rows[$cursor]}else{$null}
        switch ($key.VirtualKeyCode) {
            38 { $p=$cursor-1;while($p-ge 0-and $rows[$p].T-eq 'I'-and $cat[$rows[$p].Idx].Manual){$p--};if($p-ge 0){$cursor=$p} }
            40 { $n=$cursor+1;while($n-lt $rows.Count-and $rows[$n].T-eq 'I'-and $cat[$rows[$n].Idx].Manual){$n++};if($n-lt $rows.Count){$cursor=$n} }
            39 {
                if($curRow-and $curRow.T-eq 'S'){
                    if(-not $expanded[$curRow.Folder]){$expanded[$curRow.Folder]=$true}
                    else{$n=$cursor+1;while($n-lt $rows.Count-and $rows[$n].T-eq 'I'-and $cat[$rows[$n].Idx].Manual){$n++};if($n-lt $rows.Count-and $rows[$n].T-eq 'I'){$cursor=$n}}
                }
            }
            37 {
                if($curRow-and $curRow.T-eq 'S'){$expanded[$curRow.Folder]=$false}
                elseif($curRow-and $curRow.T-eq 'I'){
                    $f=$cat[$curRow.Idx].Folder
                    for($r2=$cursor-1;$r2-ge 0;$r2--){if($rows[$r2].T-eq 'S'-and $rows[$r2].Folder-eq $f){$cursor=$r2;break}}
                }
            }
            13 {
                if($curRow-and $curRow.T-eq 'S'){
                    $expanded[$curRow.Folder]=-not $expanded[$curRow.Folder]
                    if($expanded[$curRow.Folder]-and($cursor+1)-lt $rows.Count){$cursor++}
                } else {
                    [Console]::WriteLine('');return @{Sel=$sel.ToArray();Catalog=$cat.ToArray()}
                }
            }
            32 {
                if($curRow-and $curRow.T-eq 'S'){
                    $allOn=$curRow.SelCount-eq $curRow.Count
                    foreach($idx in $sectionItems[$curRow.Folder]){if(-not $cat[$idx].Manual){$sel[$idx]=-not $allOn}}
                } elseif($curRow-and $curRow.T-eq 'I'-and -not $cat[$curRow.Idx].Manual){
                    $sel[$curRow.Idx]=-not $sel[$curRow.Idx]
                }
            }
            191 { $filterMode=$true;$filterText='';$cursor=0;$viewTop=0 }
            80  { $packMode=$true;$packCursor=0 }
            65  { for($i=0;$i-lt $sel.Count;$i++){if(-not $cat[$i].Manual){$sel[$i]=$true}} }
            78  { for($i=0;$i-lt $sel.Count;$i++){$sel[$i]=$false} }
            121 { [Console]::WriteLine('');return @{Sel=$sel.ToArray();Catalog=$cat.ToArray()} }
            27  { [Console]::WriteLine('');return @{Sel=$sel.ToArray();Catalog=$cat.ToArray()} }
        }

    }} finally { try{[Console]::CursorVisible=$true}catch{} }
}
# ============================================================================
# ICONS   - each key is a list of URLs tried in order until one succeeds
#          Primary: official/CDN source  |  Fallback: Wikipedia 128px PNG
# ============================================================================
$IconSources = @{
    # Debian family
    'debian'         = @('https://www.debian.org/logos/openlogo-nd-100.png',
                         'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4a/Debian-OpenLogo.svg/128px-Debian-OpenLogo.svg.png')
    'ubuntu'         = @('https://assets.ubuntu.com/v1/29985a98-ubuntu-logo32.png',
                         'https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Logo-ubuntu_cof-orange-hex.svg/128px-Logo-ubuntu_cof-orange-hex.svg.png')
    'kubuntu'        = @('https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Kubuntu_logo.svg/128px-Kubuntu_logo.svg.png')
    'xubuntu'        = @('https://upload.wikimedia.org/wikipedia/commons/thumb/b/b6/Xubuntu_logo_and_wordmark.svg/128px-Xubuntu_logo_and_wordmark.svg.png')
    'lubuntu'        = @('https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Linux_Mint_logo_without_wordmark.svg/128px-Linux_Mint_logo_without_wordmark.svg.png',
                         'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Lubuntu_logo_only.svg/128px-Lubuntu_logo_only.svg.png')
    'ubuntu_mate'    = @('https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/Ubuntu_MATE_logomark.svg/128px-Ubuntu_MATE_logomark.svg.png')
    'ubuntu_budgie'  = @('https://upload.wikimedia.org/wikipedia/commons/thumb/6/6a/Ubuntu_Budgie_icon.svg/128px-Ubuntu_Budgie_icon.svg.png')
    'ubuntu_studio'  = @('https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/UbuntuStudio_hidef_logo.svg/128px-UbuntuStudio_hidef_logo.svg.png')
    'mint'           = @('https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Linux_Mint_logo_without_wordmark.svg/128px-Linux_Mint_logo_without_wordmark.svg.png')
    'mx'             = @('https://upload.wikimedia.org/wikipedia/commons/thumb/c/c7/MX_Linux_logo.svg/128px-MX_Linux_logo.svg.png')
    'popos'          = @('https://upload.wikimedia.org/wikipedia/commons/thumb/b/b3/Pop!_OS_Logo.svg/128px-Pop!_OS_Logo.svg.png')
    # RHEL family
    'proxmox'        = @('https://upload.wikimedia.org/wikipedia/commons/thumb/8/8b/Proxmox-VE_logo.svg/128px-Proxmox-VE_logo.svg.png')
    'rocky'          = @('https://upload.wikimedia.org/wikipedia/commons/thumb/6/63/Rocky_Linux_logo.svg/128px-Rocky_Linux_logo.svg.png')
    'alma'           = @('https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/AlmaLinux_Icon_Logo.svg/128px-AlmaLinux_Icon_Logo.svg.png')
    'fedora'         = @('https://upload.wikimedia.org/wikipedia/commons/thumb/4/41/Fedora_icon_%282021%29.svg/128px-Fedora_icon_%282021%29.svg.png')
    'centos'         = @('https://upload.wikimedia.org/wikipedia/commons/thumb/b/bf/Centos-logo-light.svg/128px-Centos-logo-light.svg.png')
    'oracle'         = @('https://upload.wikimedia.org/wikipedia/commons/thumb/5/50/Oracle_logo.svg/128px-Oracle_logo.svg.png')
    # Arch family
    'arch'           = @('https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/Arch_Linux_logo.svg/128px-Arch_Linux_logo.svg.png')
    'endeavour'      = @('https://upload.wikimedia.org/wikipedia/commons/thumb/a/aa/EndeavourOS-Logo.svg/128px-EndeavourOS-Logo.svg.png')
    'manjaro'        = @('https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Manjaro-logo.svg/128px-Manjaro-logo.svg.png')
    # Other Linux
    'opensuse'       = @('https://upload.wikimedia.org/wikipedia/commons/thumb/d/d0/OpenSUSE_Logo.svg/128px-OpenSUSE_Logo.svg.png')
    # Security
    'kali'           = @('https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Kali-dragon-icon.svg/128px-Kali-dragon-icon.svg.png')
    'parrot'         = @('https://upload.wikimedia.org/wikipedia/commons/thumb/2/24/Parrot_OS_Logo.svg/128px-Parrot_OS_Logo.svg.png')
    'tails'          = @('https://upload.wikimedia.org/wikipedia/commons/thumb/2/2d/Tails-logo-flat-inverted.svg/128px-Tails-logo-flat-inverted.svg.png')
    # Sysadmin
    'truenas'        = @('https://upload.wikimedia.org/wikipedia/commons/thumb/8/84/TrueNAS_Logo.svg/128px-TrueNAS_Logo.svg.png')
    'clonezilla'     = @('https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Clonezilla_logo.png/128px-Clonezilla_logo.png')
    'gparted'        = @('https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Gparted_icon.svg/128px-Gparted_icon.svg.png')
    'finnix'         = @('https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/Finnix-logo.svg/128px-Finnix-logo.svg.png')
    # Rescue
    'rescue'         = @('https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/SystemRescueCD_logo.svg/128px-SystemRescueCD_logo.svg.png')
    'hirens'         = @('https://www.hirensbootcd.org/wp-content/uploads/2019/01/hbcdpe-logo.png',
                         'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5f/Windows_logo_-_2021.svg/128px-Windows_logo_-_2021.svg.png')
    'memtest'        = @('https://upload.wikimedia.org/wikipedia/commons/thumb/6/63/Memtest86%2B_logo.svg/128px-Memtest86%2B_logo.svg.png')
    # Windows
    'windows11'      = @('https://upload.wikimedia.org/wikipedia/commons/thumb/5/5f/Windows_logo_-_2021.svg/128px-Windows_logo_-_2021.svg.png')
    'windows10'      = @('https://upload.wikimedia.org/wikipedia/commons/thumb/2/24/Windows_logo_-_2012.svg/128px-Windows_logo_-_2012.svg.png')
}

# ============================================================================
# VENTOY CONFIG GENERATORS
# ============================================================================
function Get-VentoyJsonContent {
    param([string]$themeSlug, [object[]]$SelectedIsos)

    $aliases = ($SelectedIsos | ForEach-Object {
        $f = $_.Folder -replace '\\','/'
        "    { `"image`": `"/ISO/$f/$($_.Name)`", `"alias`": `"$($_.Alias)`" }"
    }) -join ",`n"

    $kaliIso     = $SelectedIsos | Where-Object { $_.Name -like 'kali*live*' } | Select-Object -First 1
    $persistBlock = ''
    if ($kaliIso) {
        $kf = $kaliIso.Folder -replace '\\','/'
        $persistBlock = @"
  "persistence": [
    { "image": "/ISO/$kf/$($kaliIso.Name)",
      "backend": "/ventoy/persistence/kali-persistence.dat" }
  ],
"@
    }

    return @"
{
  "control": [
    { "VTOY_DEFAULT_MENU_MODE": "0" },
    { "VTOY_TREE_VIEW_MENU_STYLE": "0" },
    { "VTOY_FILT_DOT_UNDERSCORE_FILE": "1" },
    { "VTOY_SORT_CASE_SENSITIVE": "0" },
    { "VTOY_MAX_SEARCH_LEVEL": "max" },
    { "VTOY_DEFAULT_SEARCH_ROOT": "/ISO" },
    { "VTOY_MENU_TIMEOUT": "30" }
  ],
  "theme": {
    "file": "/ventoy/theme/$themeSlug/theme.txt",
    "gfxmode": "1920x1080",
    "display_mode": "GUI",
    "ventoy_color": "#7c3aed"
  },
$persistBlock  "menu_alias": [
    { "dir": "/ISO/Linux",         "alias": "Linux Distros" },
    { "dir": "/ISO/Linux/Debian",  "alias": "  Debian Family" },
    { "dir": "/ISO/Linux/RHEL",    "alias": "  RHEL Family" },
    { "dir": "/ISO/Linux/Arch",    "alias": "  Arch Family" },
    { "dir": "/ISO/Linux/Other",   "alias": "  Other Linux" },
    { "dir": "/ISO/Security",      "alias": "Pentest & Security" },
    { "dir": "/ISO/Sysadmin",      "alias": "Sysadmin Tools" },
    { "dir": "/ISO/Rescue",        "alias": "Rescue & Recovery" },
    { "dir": "/ISO/Windows",       "alias": "Windows" },
    { "dir": "/ISO/Custom",        "alias": "Custom ISOs" },
$aliases
  ],
  "menu_class": [
    { "key": "debian",           "class": "debian" },
    { "key": "kubuntu",          "class": "kubuntu" },
    { "key": "xubuntu",          "class": "xubuntu" },
    { "key": "lubuntu",          "class": "lubuntu" },
    { "key": "ubuntu-mate",      "class": "ubuntu_mate" },
    { "key": "ubuntu-budgie",    "class": "ubuntu_budgie" },
    { "key": "ubuntustudio",     "class": "ubuntu_studio" },
    { "key": "ubuntu",           "class": "ubuntu" },
    { "key": "linuxmint",        "class": "mint" },
    { "key": "MX-",              "class": "mx" },
    { "key": "pop-os",           "class": "popos" },
    { "key": "proxmox",          "class": "proxmox" },
    { "key": "Rocky",            "class": "rocky" },
    { "key": "AlmaLinux",        "class": "alma" },
    { "key": "Fedora",           "class": "fedora" },
    { "key": "CentOS-Stream",    "class": "centos" },
    { "key": "OracleLinux",      "class": "oracle" },
    { "key": "archlinux",        "class": "arch" },
    { "key": "Endeavour",        "class": "endeavour" },
    { "key": "manjaro",          "class": "manjaro" },
    { "key": "openSUSE",         "class": "opensuse" },
    { "key": "purple",           "class": "kali" },
    { "key": "kali",             "class": "kali" },
    { "key": "Parrot",           "class": "parrot" },
    { "key": "tails",            "class": "tails" },
    { "key": "TrueNAS",          "class": "truenas" },
    { "key": "clonezilla",       "class": "clonezilla" },
    { "key": "gparted",          "class": "gparted" },
    { "key": "systemrescue",     "class": "rescue" },
    { "key": "HBCD",             "class": "hirens" },
    { "key": "memtest",          "class": "memtest" },
    { "key": "finnix",           "class": "finnix" },
    { "key": "Win11",            "class": "windows11" },
    { "key": "Win10",            "class": "windows10" },
    { "key": "LTSC",             "class": "windows_ltsc" }
  ]
}
"@
}

function Get-ThemeTxtContent {
    param([string]$title)
    return @"
title-text: ""
desktop-color: "#0a0612"
terminal-font: "Unifont Regular 16"

+ boot_menu {
    left = 5%
    top = 18%
    width = 60%
    height = 65%
    item_font = "Unifont Regular 16"
    item_color = "#e9d5ff"
    selected_item_color = "#ffffff"
    icon_width = 32
    icon_height = 32
    item_icon_space = 14
    item_height = 36
    item_padding = 4
    item_spacing = 2
}

+ label {
    top = 95%
    left = 5%
    width = 90%
    align = "left"
    color = "#a78bfa"
    text = "$title  ::  ^v Navigate  ::  Enter Boot  ::  F5 Tools"
    font = "Unifont Regular 12"
}
"@
}

# ============================================================================
# MAIN
# ============================================================================
Write-Banner

if (-not (Test-Admin)) {
    Write-Err "Run as Administrator / Ejecuta como Administrador."
    Read-Host "ENTER"
    exit 1
}

# --- Language ---
if ([string]::IsNullOrWhiteSpace($Language)) {
    $inp = Read-Host ($LANG.en.LangAsk)
    $Language = if ($inp.Trim() -in @('es','ES')) { 'es' } else { 'en' }
}
$L = $LANG[$Language.ToLower()]
if (-not $L) { $L = $LANG.en }
$script:L = $L

# --- Title ---
if ([string]::IsNullOrWhiteSpace($Title)) {
    Write-Host ""
    Write-Host ("  {0}" -f $L.TitleAsk) -ForegroundColor Cyan
    $inp  = Read-Host ($L.TitleRead)
    $Title = if ([string]::IsNullOrWhiteSpace($inp)) { 'MYBOOT' } else { $inp.Trim() }
}
$script:Title = $Title
$themeSlug = ($Title -replace '[^a-zA-Z0-9_-]', '_').ToLower()

# --- Download mode (direct-to-USB vs cache+copy) ---
if ($DirectToUSB) {
    $script:UseDirectMode = $true
} elseif ($UseCache) {
    $script:UseDirectMode = $false
} else {
    Write-Host ""
    Write-Host ("  " + $L.ModeAsk) -ForegroundColor Cyan
    Write-Host $L.ModeDirect -ForegroundColor DarkGray
    Write-Host $L.ModeCache  -ForegroundColor DarkGray
    $inp = Read-Host $L.ModePrompt
    $script:UseDirectMode = ($inp.Trim() -notin @('c','C','cache','Cache','CACHE'))
}
if ($script:UseDirectMode) { Write-Ok $L.ModeDirectOk } else { Write-Ok $L.ModeCacheOk }

# --- Download directory (still used for Ventoy installer, Fido, zip extraction) ---
if ([string]::IsNullOrWhiteSpace($DownloadDir)) {
    $defaultDir = if ($onLinux -or $onMac) { "$HOME/${Title}_cache" } else { "$env:USERPROFILE\${Title}_cache" }
    Write-Host ""
    Write-Host ("  " + ($L.DirAsk -f 40)) -ForegroundColor Cyan
    $inp        = Read-Host ($L.DirRead -f $defaultDir)
    $DownloadDir = if ([string]::IsNullOrWhiteSpace($inp)) { $defaultDir } else { $inp.Trim() }
}

# --- Persistence ---
if (-not $SkipPersistence.IsPresent) {
    Write-Host ""
    Write-Host ("  " + $L.PersistAsk) -ForegroundColor Cyan -NoNewline
    $inp = Read-Host
    if ($inp.Trim() -in @('n','N','no','No','NO')) {
        $SkipPersistence = $true
    } else {
        Write-Host ("  " + $L.PersistSzAsk) -ForegroundColor Cyan
        $inp = Read-Host ($L.PersistSzRead)
        if (-not [string]::IsNullOrWhiteSpace($inp)) {
            $parsed = 0
            if ([int]::TryParse($inp.Trim(), [ref]$parsed) -and $parsed -gt 0) {
                $PersistenceSizeMB = $parsed
            }
        }
    }
}

$freeGB = Get-DriveFreeGB $DownloadDir
if ($freeGB) {
    Write-Host ("  " + ($L.DirFree -f "$freeGB GB")) -ForegroundColor DarkGray
    if ($freeGB -lt 15) { Write-Warn2 ($L.DirWarn -f 15) }
}

Write-Banner
Write-Config

# --- Create cache directory ---
try {
    if (-not (Test-Path $DownloadDir)) {
        New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    }
    Write-Ok ($L.CacheOk -f $DownloadDir)
} catch {
    Write-Err "Cannot create $DownloadDir : $($_.Exception.Message)"
    Read-Host "ENTER"; exit 1
}

# --- Resolve latest versions & build catalog ---
Write-Step $L.Resolving
$catalog = @(Get-IsoCatalog) + @(Get-CustomIsos)

# --- ISO selection ---
$menuResult  = Show-IsoMenu -Catalog $catalog
$sel         = $menuResult.Sel
$catalog     = $menuResult.Catalog   # may include custom ISOs added interactively

$selectedIsos = @()
for ($ii = 0; $ii -lt $catalog.Count; $ii++) {
    if ($sel[$ii]) { $selectedIsos += $catalog[$ii] }
}

# === 1) Ventoy ===
if (-not $SkipVentoyInstall) {
    Write-Step $L.Step1
    $vtUrl = $null; $vtName = $null
    $vtPattern = if ($onLinux -or $onMac) { 'linux\.tar\.gz$' } else { 'windows\.zip$' }
    $vtFallbackVer = '1.1.11'
    try {
        $rel   = Invoke-RestMethod 'https://api.github.com/repos/ventoy/Ventoy/releases/latest' `
                     -UseBasicParsing -TimeoutSec 30
        $asset = $rel.assets | Where-Object { $_.name -match $vtPattern } | Select-Object -First 1
        $vtUrl = $asset.browser_download_url; $vtName = $asset.name
        Write-Ok "Ventoy $($rel.tag_name)"
    } catch {
        if ($onLinux -or $onMac) {
            $vtName = "ventoy-${vtFallbackVer}-linux.tar.gz"
        } else {
            $vtName = "ventoy-${vtFallbackVer}-windows.zip"
        }
        $vtUrl = "https://github.com/ventoy/Ventoy/releases/download/v${vtFallbackVer}/$vtName"
        Write-Warn2 $L.VentoyFallback
    }

    $vtArchive = Join-Path $DownloadDir $vtName
    if (-not (Test-Path $vtArchive)) {
        Invoke-DownloadMulti -Urls @($vtUrl) -OutFile $vtArchive -MinBytes 1MB | Out-Null
    }
    try {
        if (Test-Path $vtArchive) {
            if ($onLinux -or $onMac) {
                $null = New-Item -ItemType Directory -Path $DownloadDir -Force
                tar -xzf $vtArchive -C $DownloadDir 2>/dev/null
            } else {
                Expand-Archive -Path $vtArchive -DestinationPath $DownloadDir -Force -ErrorAction Stop
            }
            Write-Ok $L.VentoyExtract
        }
    } catch { Write-Warn2 "Extract error: $($_.Exception.Message)" }

    # === 2) Ventoy installer ===
    Write-Step $L.Step2
    if ($onLinux -or $onMac) {
        $sh = Get-ChildItem -Path $DownloadDir -Recurse -Filter 'Ventoy2Disk.sh' -ErrorAction SilentlyContinue |
              Select-Object -First 1 -ExpandProperty FullName
        if (-not $sh) {
            Write-Err $L.VentoyMissing
        } else {
            Write-Ok "Found: $sh"
            if ([string]::IsNullOrWhiteSpace($UsbDevice)) {
                Write-Host ""
                # Show block devices to help the user choose
                try { lsblk -o NAME,SIZE,RM,LABEL,VENDOR,MODEL 2>/dev/null } catch {}
                Write-Host ""
                $UsbDevice = (Read-Host $L.VentoyOpenLin).Trim()
            }
            if (-not [string]::IsNullOrWhiteSpace($UsbDevice)) {
                Write-Host "  sudo bash $sh -I $UsbDevice" -ForegroundColor DarkGray
                try { sudo bash $sh -I $UsbDevice; Write-Ok "Done" }
                catch { Write-Warn2 $_.Exception.Message }
            } else {
                Write-Info "Skipping Ventoy install (no device specified)"
            }
        }
    } else {
        $exe = Get-ChildItem -Path $DownloadDir -Recurse -Filter 'Ventoy2Disk.exe' -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName
        if (-not $exe) {
            Write-Err $L.VentoyMissing
        } else {
            Write-Ok "Found: $exe"
            Read-Host $L.VentoyOpen
            try { Start-Process -FilePath $exe -Wait; Write-Ok "Done" }
            catch { Write-Warn2 $_.Exception.Message }
        }
    }
} else {
    Write-Info "Skipping Ventoy install (-SkipVentoyInstall)"
}

# === 3) Detect USB ===
Write-Step $L.Step3
$usbRoot = $null
if ($onLinux -or $onMac) {
    # Linux/macOS: use mount point
    if ($UsbMountPoint) {
        $usbRoot = $UsbMountPoint.TrimEnd('/')
        Write-Ok "USB: $usbRoot"
    } else {
        # Try to auto-detect by label
        try {
            $lsblkJson = lsblk -J -o NAME,LABEL,MOUNTPOINTS,SIZE,RM 2>/dev/null | ConvertFrom-Json
            foreach ($dev in $lsblkJson.blockdevices) {
                $parts = if ($dev.children) { $dev.children } else { @($dev) }
                foreach ($part in $parts) {
                    $label = $part.label
                    $mps   = if ($part.mountpoints) { $part.mountpoints } else { @($part.mountpoint) }
                    $mp    = $mps | Where-Object { $_ } | Select-Object -First 1
                    if ($label -in @('Ventoy','VENTOY','ventoy') -and $mp) {
                        $usbRoot = $mp; break
                    }
                }
                if ($usbRoot) { break }
            }
        } catch {}
        if ($usbRoot) {
            Write-Ok "USB: $usbRoot"
        } else {
            Write-Warn2 $L.NoUsb
            try { lsblk -o NAME,SIZE,RM,LABEL,MOUNTPOINTS 2>/dev/null } catch {}
            Write-Host ""
            $mp = (Read-Host $L.UsbPromptLin).Trim()
            if ([string]::IsNullOrWhiteSpace($mp)) { Write-Err "Aborted."; exit 1 }
            $usbRoot = $mp.TrimEnd('/')
        }
    }
} else {
    # Windows: use drive letter
    if ($UsbDriveLetter) {
        $usbRoot = $UsbDriveLetter.TrimEnd(':') + ':'
        Write-Ok "USB: $usbRoot"
    } else {
        try {
            $vol = Get-Volume -ErrorAction SilentlyContinue |
                   Where-Object { $_.FileSystemLabel -in @('Ventoy','VENTOY') } | Select-Object -First 1
            if ($vol) {
                $usbRoot = $vol.DriveLetter + ':'
                Write-Ok "USB: $usbRoot ($(Format-Bytes $vol.Size))"
            }
        } catch {}
        if (-not $usbRoot) {
            Write-Warn2 $L.NoUsb
            Get-Volume | Where-Object DriveLetter |
                Format-Table DriveLetter, FileSystemLabel,
                    @{N='Size';E={Format-Bytes $_.Size}},
                    @{N='Free';E={Format-Bytes $_.SizeRemaining}}
            $ltr = Read-Host $L.UsbPrompt
            if ([string]::IsNullOrWhiteSpace($ltr)) { Write-Err "Aborted."; Read-Host "ENTER"; exit 1 }
            $usbRoot = $ltr.TrimEnd(':') + ':'
        }
    }
}
if (-not (Test-Path $usbRoot)) {
    Write-Err ($L.UsbNoAccess -f $usbRoot); Read-Host "ENTER"; exit 1
}

$usbFreeGB = Get-DriveFreeGB $usbRoot
$neededMB  = 0; foreach ($iso in $selectedIsos) { if ($iso.SizeMB) { $neededMB += $iso.SizeMB } }
$neededGB  = [Math]::Round($neededMB / 1024.0, 1)
Write-Info ($L.DirFree -f "$usbFreeGB GB  |  ISOs: ~$neededGB GB")
if ($usbFreeGB -and $usbFreeGB -lt ($neededGB * 0.9)) { Write-Warn2 ($L.DirWarn -f $neededGB) }

# Create folder structure on USB
$customFolders = $selectedIsos | Where-Object { $_.Custom } |
                 ForEach-Object { "ISO\$($_.Folder)" } | Select-Object -Unique
$folders = @(
    'ISO\Linux\Debian','ISO\Linux\RHEL','ISO\Linux\Arch','ISO\Linux\Other',
    'ISO\Security','ISO\Sysadmin','ISO\Rescue','ISO\Windows','ISO\Custom'
) + $customFolders + @(
    'ventoy',"ventoy\theme\$themeSlug","ventoy\theme\$themeSlug\icons",'ventoy\persistence'
)
foreach ($f in $folders) {
    $p = Join-Path $usbRoot $f
    if (-not (Test-Path $p)) { try { New-Item -ItemType Directory -Path $p -Force | Out-Null } catch {} }
}

# === 4) Download ISOs ===
Write-Step $L.Step4
$results = @()
$ii = 0
foreach ($iso in $catalog) {
    $ii++
    Write-Step ($L.StepIso -f $ii, $catalog.Count, $iso.Alias)

    if ($iso.Manual) {
        $dest = Join-Path $usbRoot "ISO\$($iso.Folder)"
        if ($iso.ManualLtsc) {
            Write-Warn2 $L.LtscNote
            Write-Info  $L.LtscUrl
            Write-Info  ($L.LtscDest -f $usbRoot)
        } else {
            Write-Warn2 ($L.ManualMsg -f $dest)
        }
        $results += [PSCustomObject]@{ ISO=$iso.Alias; Status='MANUAL'; Note='Manual download' }
        continue
    }

    $isoIdx = [array]::IndexOf($catalog, $iso)
    if (-not $sel[$isoIdx]) {
        Write-Info $L.SkippedMsg
        $results += [PSCustomObject]@{ ISO=$iso.Alias; Status='SKIP'; Note='' }
        continue
    }

    # Final destination on USB
    $destDir  = Join-Path $usbRoot ('ISO\' + $iso.Folder)
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    $destPath = Join-Path $destDir $iso.Name

    # Where the download lands. Direct-to-USB unless the ISO needs unzipping
    # (zips need a temp extraction area, so they always go through cache first).
    $useDirect = $script:UseDirectMode -and -not $iso.Unzip
    $localPath = if ($useDirect) { $destPath } else { Join-Path $DownloadDir $iso.Name }
    if ($useDirect) { Write-Info $L.DownloadingDirect }

    $ok = $false

    if ($iso.Fido) {
        try { $ok = Invoke-FidoDownload -OutFile $localPath -Iso $iso }
        catch { Write-Err "Fido exception: $($_.Exception.Message)" }
        if (-not $ok) {
            $results += [PSCustomObject]@{ ISO=$iso.Alias; Status='FAILED'; Note='Fido failed' }
            continue
        }
    } else {
        try { $ok = Invoke-DownloadMulti -Urls $iso.Urls -OutFile $localPath }
        catch { Write-Err "Exception: $($_.Exception.Message)" }
    }

    if ($ok -and $iso.Unzip) {
        try {
            Write-Info "Extracting zip..."
            $ext = Join-Path $DownloadDir "_x_$($iso.Name)"
            if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
            Expand-Archive -Path $localPath -DestinationPath $ext -Force
            $real = Get-ChildItem -Path $ext -Filter '*.iso' -Recurse | Select-Object -First 1
            if ($real) { Move-Item $real.FullName $localPath -Force }
            Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
        } catch { Write-Warn2 "Unzip failed: $($_.Exception.Message)" }
    }

    if (-not $ok) {
        $results += [PSCustomObject]@{ ISO=$iso.Alias; Status='FAILED'; Note='All URLs failed' }
        continue
    }

    # Direct mode: file is already at destPath, nothing to copy
    if ($localPath -eq $destPath) {
        Write-Ok $L.Copied
        $results += [PSCustomObject]@{ ISO=$iso.Alias; Status='OK'; Note='direct' }
        continue
    }

    try {
        if ((Test-Path $destPath) -and (Get-Item $destPath).Length -eq (Get-Item $localPath).Length) {
            Write-Info $L.AlreadyUsb
        } else {
            Write-Info $L.Copying
            Copy-Item $localPath $destPath -Force -ErrorAction Stop
            Write-Ok $L.Copied
        }
        $results += [PSCustomObject]@{ ISO=$iso.Alias; Status='OK'; Note='' }
    } catch {
        Write-Err "Copy error: $($_.Exception.Message)"
        $results += [PSCustomObject]@{ ISO=$iso.Alias; Status='COPY_FAIL'; Note=$_.Exception.Message }
    }
}

# === 5) Icons ===
Write-Step $L.Step5
$iconsDir = Join-Path $usbRoot "ventoy\theme\$themeSlug\icons"
if (-not (Test-Path $iconsDir)) { New-Item -ItemType Directory -Path $iconsDir -Force | Out-Null }

foreach ($name in $IconSources.Keys) {
    $out = Join-Path $iconsDir "$name.png"
    if ((Test-Path $out) -and (Get-Item $out).Length -gt 1KB) {
        Write-Info "$name  already exists"
        continue
    }
    $saved = $false
    foreach ($url in $IconSources[$name]) {
        try {
            $tmp = "$out.tmp"
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing `
                -TimeoutSec 20 -MaximumRedirection 5 -ErrorAction Stop
            # Validate: must be a real image (PNG/JPEG magic bytes or >2KB)
            if ((Test-Path $tmp) -and (Get-Item $tmp).Length -gt 2KB) {
                Move-Item $tmp $out -Force
                Write-Ok "$name"
                $saved = $true
                break
            }
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        } catch {
            Remove-Item "$out.tmp" -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $saved) { Write-Warn2 "$name  all sources failed" }
}

# Derived icons (copies)
$iconCopies = @{
    'kali_purple'  = 'kali'
    'windows_ltsc' = 'windows11'
    'debian11'     = 'debian'
    'lubuntu'      = 'lubuntu'   # already in IconSources, this is harmless
}
foreach ($dst in $iconCopies.Keys) {
    $src = Join-Path $iconsDir "$($iconCopies[$dst]).png"
    $out = Join-Path $iconsDir "$dst.png"
    if ((Test-Path $src) -and -not (Test-Path $out)) {
        try { Copy-Item $src $out -Force } catch {}
    }
}

# === 6) Config files ===
Write-Step $L.Step6
try {
    Get-VentoyJsonContent -themeSlug $themeSlug -SelectedIsos $selectedIsos |
        Set-Content (Join-Path $usbRoot 'ventoy\ventoy.json') -Encoding UTF8
    Get-ThemeTxtContent -title $Title |
        Set-Content (Join-Path $usbRoot "ventoy\theme\$themeSlug\theme.txt") -Encoding UTF8
    Write-Ok $L.CfgOk
} catch { Write-Err "Config error: $($_.Exception.Message)" }

# === 7) Persistence ===
if (-not $SkipPersistence) {
    Write-Step ($L.Step7 + "  ($PersistenceSizeMB MB)")
    if ($onLinux -or $onMac) {
        Write-Info "Persistence on Linux/macOS requires a real ext4 partition (fsutil is Windows-only)."
        Write-Info "Run these commands manually after the USB is built:"
        $L.PersistSteps | ForEach-Object { Write-Info $_ }
    } else {
        $persPath = Join-Path $usbRoot 'ventoy\persistence\kali-persistence.dat'
        if (Test-Path $persPath) {
            Write-Info $L.PersistSkip
        } else {
            try {
                $bytes = [int64]$PersistenceSizeMB * 1MB
                & fsutil file createnew $persPath $bytes 2>&1 | Out-Null
                if (Test-Path $persPath) {
                    Write-Ok $L.PersistOk
                    $L.PersistSteps | ForEach-Object { Write-Info $_ }
                } else {
                    Write-Warn2 "fsutil failed (out of space?)"
                }
            } catch { Write-Warn2 "Persistence error: $($_.Exception.Message)" }
        }
    }
}

# === Summary ===
Write-Host "`n$('='*70)" -ForegroundColor Magenta
Write-Host ("                    {0}" -f $L.Summary) -ForegroundColor Magenta
Write-Host ('='*70) -ForegroundColor Magenta
$results | Format-Table -AutoSize -Wrap

$okC   = ($results | Where-Object Status -eq 'OK').Count
$failC = ($results | Where-Object Status -eq 'FAILED').Count
$cfC   = ($results | Where-Object Status -eq 'COPY_FAIL').Count
$skipC = ($results | Where-Object Status -eq 'SKIP').Count
$manC  = ($results | Where-Object Status -eq 'MANUAL').Count

Write-Host "  OK=$okC  FAILED=$failC  COPY_FAIL=$cfC  SKIP=$skipC  MANUAL=$manC" -ForegroundColor White

if ($failC -gt 0 -or $cfC -gt 0) {
    Write-Warn2 $L.RetryTip
    if ($onLinux -or $onMac) {
        Write-Info "  pwsh Build-MultibootUSB.ps1 -Language $Language -Title `"$Title`" -DownloadDir `"$DownloadDir`" -UsbMountPoint `"$usbRoot`" -SkipVentoyInstall"
    } else {
        Write-Info "  .\Build-MultibootUSB.ps1 -Language $Language -Title `"$Title`" -DownloadDir `"$DownloadDir`" -UsbDriveLetter $($usbRoot.TrimEnd(':')) -SkipVentoyInstall"
    }
}

try {
    if ($onLinux -or $onMac) {
        $dfOut = df -h $usbRoot 2>/dev/null | Select-Object -Last 1
        if ($dfOut) { Write-Info "USB: $dfOut" }
    } else {
        $vol = Get-Volume -DriveLetter ($usbRoot.TrimEnd(':')) -ErrorAction SilentlyContinue
        if ($vol) { Write-Info "USB: $(Format-Bytes $vol.SizeRemaining) free / $(Format-Bytes $vol.Size) total" }
    }
} catch {}

Write-Ok ($L.DoneMsg -f $Title, $usbRoot)
Write-Info ($L.ManualWin -f $usbRoot)
Write-Host ""
Read-Host "ENTER"
