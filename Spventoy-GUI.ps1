# ============================================================================
#  Spventoy-GUI.ps1 — WPF graphical front-end for Build-MultibootUSB.ps1
#
#  Collects all build parameters in a window, then launches the CLI script
#  as a subprocess and streams its output into a log panel.
# ============================================================================
#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ─── Resolve our own folder (works for both .ps1 and PS2EXE-compiled .exe) ─
# When compiled with PS2EXE, $PSScriptRoot is empty. Fall back to the path of
# the executing process / assembly so we can still find sibling files
# (Build-MultibootUSB.ps1, custom-isos.json, icons/, etc.).
function Get-AppRoot {
    if ($PSScriptRoot)                             { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path)              { return Split-Path -Parent $MyInvocation.MyCommand.Path }
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exe) { return Split-Path -Parent $exe }
    } catch {}
    try {
        $asm = [System.Reflection.Assembly]::GetExecutingAssembly().Location
        if ($asm) { return Split-Path -Parent $asm }
    } catch {}
    return (Get-Location).Path
}
$script:AppRoot = Get-AppRoot

# ─── Load WPF ───────────────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# ─── Localized strings ─────────────────────────────────────────────────────
$STRINGS = @{
    en = @{
        WindowTitle    = 'Spventoy - Multiboot USB Builder'
        Header         = 'SPVENTOY'
        SubHeader      = 'MULTIBOOT  USB  BUILDER'
        SectionForm    = 'Build settings'
        SectionIsos    = 'ISO selection'
        SectionLog     = 'Output'
        LblTitle       = 'USB title'
        LblMode        = 'Download mode'
        ModeDirect     = 'Direct to USB (faster, single build)'
        ModeCache      = 'Cache + copy (reusable for multiple USBs)'
        LblDrive       = 'USB drive'
        BtnRefresh     = 'Refresh'
        LblPersist     = 'Create Kali persistence partition'
        LblPersistSize = 'Persistence size (MB)'
        BtnRecommended = 'Recommended'
        BtnAll         = 'All'
        BtnNone        = 'None'
        BtnAddCustom   = '+ Add custom ISO'
        BtnEditJson    = 'Edit JSON'
        BtnUseLocal    = 'Use local file'
        BtnClearLocal  = 'Clear local file'
        LocalSet       = '[local]'
        TipUseLocal    = 'Use a local ISO file instead of downloading. Click to pick / change. Right-click to clear.'
        LblCacheDir    = 'Cache directory'
        BtnBrowseDir   = 'Browse...'
        SelectedSummary= '{0} selected, ~{1} GB'
        BtnStart       = 'Start build'
        BtnStop        = 'Stop'
        BtnClose       = 'Close'
        ErrTitle       = 'Title is required.'
        ErrDrive       = 'Pick a USB drive.'
        ErrNoIsos      = 'Select at least one ISO.'
        ErrNotAdmin    = 'This GUI must be run as Administrator (the build needs to write to the USB).'
        ErrCustomFields= 'Alias, file name, size and at least one URL are required.'
        WarnRunning    = 'A build is already running. Stop it first or wait for it to finish.'
        StatusReady    = 'Ready'
        StatusRunning  = 'Building... (do not unplug the USB)'
        StatusDone     = 'Build finished'
        StatusFailed   = 'Build failed (exit {0})'
        StatusStopped  = 'Build stopped by user'
        ConfirmStop    = 'Stop the running build? The USB may be left in an incomplete state.'
        ConfirmClose   = 'A build is in progress. Close anyway?'
        DlgAddTitle    = 'Add custom ISO'
        DlgAlias       = 'Display name (alias)'
        DlgFileName    = 'File name on the USB (e.g. my-os.iso)'
        DlgFolder      = 'Subfolder under /ISO/ (default: Custom)'
        DlgSize        = 'Approximate size in MB'
        DlgUrls        = 'Download URL(s) - one per line'
        DlgCancel      = 'Cancel'
        DlgAdd         = 'Add'
        CatCustom      = 'Custom'
        VentoyInstalled    = 'OK Ventoy already installed on this drive'
        VentoyNotInstalled = 'WARN Ventoy is NOT installed on this drive'
        BtnInstallVentoy   = 'Install Ventoy'
        ConfirmInstallVentoy = 'WARNING: this will WIPE drive {0} completely. Continue?'
        VentoyInstallSpawned = 'Ventoy2Disk has been opened. Install it on the chosen drive, then close it and click Refresh.'
    }
    es = @{
        WindowTitle    = 'Spventoy - Constructor de USB Multiboot'
        Header         = 'SPVENTOY'
        SubHeader      = 'CONSTRUCTOR  DE  USB  MULTIBOOT'
        SectionForm    = 'Configuracion'
        SectionIsos    = 'Seleccion de ISOs'
        SectionLog     = 'Salida'
        LblTitle       = 'Titulo de la USB'
        LblMode        = 'Modo de descarga'
        ModeDirect     = 'Directo al USB (mas rapido, una sola USB)'
        ModeCache      = 'Cache + copia (reutilizable para varias USBs)'
        LblDrive       = 'Unidad USB'
        BtnRefresh     = 'Refrescar'
        LblPersist     = 'Crear particion de persistencia Kali'
        LblPersistSize = 'Tamano persistencia (MB)'
        BtnRecommended = 'Recomendadas'
        BtnAll         = 'Todas'
        BtnNone        = 'Ninguna'
        BtnAddCustom   = '+ Anadir ISO custom'
        BtnEditJson    = 'Editar JSON'
        BtnUseLocal    = 'Usar archivo local'
        BtnClearLocal  = 'Borrar archivo local'
        LocalSet       = '[local]'
        TipUseLocal    = 'Usar un archivo ISO local en lugar de descargar. Click para elegir / cambiar. Click derecho para borrar.'
        LblCacheDir    = 'Directorio del cache'
        BtnBrowseDir   = 'Examinar...'
        SelectedSummary= '{0} seleccionadas, ~{1} GB'
        BtnStart       = 'Empezar'
        BtnStop        = 'Parar'
        BtnClose       = 'Cerrar'
        ErrTitle       = 'El titulo es obligatorio.'
        ErrDrive       = 'Selecciona una unidad USB.'
        ErrNoIsos      = 'Selecciona al menos una ISO.'
        ErrNotAdmin    = 'Esta GUI requiere permisos de Administrador (el build escribe al USB).'
        ErrCustomFields= 'Alias, nombre de archivo, tamano y al menos una URL son obligatorios.'
        WarnRunning    = 'Ya hay un build en curso. Detenlo primero o espera a que termine.'
        StatusReady    = 'Listo'
        StatusRunning  = 'Construyendo... (no desconectes la USB)'
        StatusDone     = 'Build terminado'
        StatusFailed   = 'Build fallo (exit {0})'
        StatusStopped  = 'Build detenido por el usuario'
        ConfirmStop    = 'Detener el build en curso? La USB puede quedar en estado incompleto.'
        ConfirmClose   = 'Hay un build en curso. Cerrar de todos modos?'
        DlgAddTitle    = 'Anadir ISO custom'
        DlgAlias       = 'Nombre visible (alias)'
        DlgFileName    = 'Nombre de archivo en la USB (ej. mi-os.iso)'
        DlgFolder      = 'Subcarpeta bajo /ISO/ (por defecto: Custom)'
        DlgSize        = 'Tamano aproximado en MB'
        DlgUrls        = 'URL(s) de descarga - una por linea'
        DlgCancel      = 'Cancelar'
        DlgAdd         = 'Anadir'
        CatCustom      = 'Custom'
        VentoyInstalled    = 'OK Ventoy ya instalado en esta unidad'
        VentoyNotInstalled = 'AVISO Ventoy NO esta instalado en esta unidad'
        BtnInstallVentoy   = 'Instalar Ventoy'
        ConfirmInstallVentoy = 'AVISO: esto FORMATEARA por completo la unidad {0}. Continuar?'
        VentoyInstallSpawned = 'Ventoy2Disk se ha abierto. Instalalo en la unidad elegida, ciearralo y pulsa Refrescar.'
    }
}

$script:Lang = 'es'
function L($key) { $STRINGS[$script:Lang][$key] }

# ─── ISO catalog (mirrors Build-MultibootUSB.ps1) ──────────────────────────
# Cat: category for grouping in the UI
# Rec: included in the "Recommended" preset
# Aliases must match the .ps1 catalog EXACTLY for -SelectedIsoAliases to work.

$script:ISO_CATALOG = @(
    # ── Debian 13 ──
    @{ Alias='Debian 13 Trixie   - Xfce';            Cat='Linux / Debian';   Size=4000; Rec=$false }
    @{ Alias='Debian 13 Trixie   - GNOME';           Cat='Linux / Debian';   Size=4500; Rec=$true  }
    @{ Alias='Debian 13 Trixie   - KDE Plasma';      Cat='Linux / Debian';   Size=4500; Rec=$false }
    @{ Alias='Debian 13 Trixie   - Cinnamon';        Cat='Linux / Debian';   Size=4000; Rec=$false }
    @{ Alias='Debian 13 Trixie   - MATE';            Cat='Linux / Debian';   Size=4000; Rec=$false }
    @{ Alias='Debian 13 Trixie   - LXQt';            Cat='Linux / Debian';   Size=3500; Rec=$false }
    @{ Alias='Debian 13 Trixie   - LXDE';            Cat='Linux / Debian';   Size=3000; Rec=$false }
    @{ Alias='Debian 13 Trixie   - Standard (no DE)';Cat='Linux / Debian';   Size=1500; Rec=$false }
    # ── Debian 12 ──
    @{ Alias='Debian 12 Bookworm   - Xfce';          Cat='Linux / Debian';   Size=4000; Rec=$false }
    @{ Alias='Debian 12 Bookworm   - GNOME';         Cat='Linux / Debian';   Size=4500; Rec=$false }
    @{ Alias='Debian 12 Bookworm   - KDE Plasma';    Cat='Linux / Debian';   Size=4500; Rec=$false }
    @{ Alias='Debian 12 Bookworm   - Cinnamon';      Cat='Linux / Debian';   Size=4000; Rec=$false }
    @{ Alias='Debian 12 Bookworm   - MATE';          Cat='Linux / Debian';   Size=4000; Rec=$false }
    @{ Alias='Debian 12 Bookworm   - LXQt';          Cat='Linux / Debian';   Size=3500; Rec=$false }
    @{ Alias='Debian 12 Bookworm   - LXDE';          Cat='Linux / Debian';   Size=3000; Rec=$false }
    @{ Alias='Debian 12 Bookworm   - Standard';      Cat='Linux / Debian';   Size=1500; Rec=$false }
    # ── Debian 11 ──
    @{ Alias='Debian 11 Bullseye   - Xfce';          Cat='Linux / Debian';   Size=3500; Rec=$false }
    @{ Alias='Debian 11 Bullseye   - GNOME';         Cat='Linux / Debian';   Size=4000; Rec=$false }
    @{ Alias='Debian 11 Bullseye   - KDE Plasma';    Cat='Linux / Debian';   Size=4000; Rec=$false }
    @{ Alias='Debian 11 Bullseye   - MATE';          Cat='Linux / Debian';   Size=3500; Rec=$false }
    @{ Alias='Debian 11 Bullseye   - Standard';      Cat='Linux / Debian';   Size=1200; Rec=$false }
    # ── Ubuntu ──
    @{ Alias='Ubuntu 24.04 LTS   - Desktop (GNOME)'; Cat='Linux / Ubuntu';   Size=5000; Rec=$true  }
    @{ Alias='Ubuntu 24.04 LTS   - Server';          Cat='Linux / Ubuntu';   Size=2000; Rec=$true  }
    @{ Alias='Ubuntu 22.04 LTS   - Desktop (GNOME)'; Cat='Linux / Ubuntu';   Size=4500; Rec=$false }
    @{ Alias='Ubuntu 22.04 LTS   - Server';          Cat='Linux / Ubuntu';   Size=1500; Rec=$false }
    @{ Alias='Ubuntu 20.04 LTS   - Desktop (GNOME)'; Cat='Linux / Ubuntu';   Size=3000; Rec=$false }
    @{ Alias='Ubuntu 20.04 LTS   - Server';          Cat='Linux / Ubuntu';   Size=1200; Rec=$false }
    # ── Ubuntu flavors ──
    @{ Alias='Kubuntu 24.04 LTS   - KDE Plasma';     Cat='Linux / Ubuntu flavors'; Size=4500; Rec=$false }
    @{ Alias='Kubuntu 22.04 LTS   - KDE Plasma';     Cat='Linux / Ubuntu flavors'; Size=4000; Rec=$false }
    @{ Alias='Kubuntu 20.04 LTS   - KDE Plasma';     Cat='Linux / Ubuntu flavors'; Size=3000; Rec=$false }
    @{ Alias='Xubuntu 24.04 LTS   - Xfce';           Cat='Linux / Ubuntu flavors'; Size=3500; Rec=$false }
    @{ Alias='Xubuntu 22.04 LTS   - Xfce';           Cat='Linux / Ubuntu flavors'; Size=3000; Rec=$false }
    @{ Alias='Xubuntu 20.04 LTS   - Xfce';           Cat='Linux / Ubuntu flavors'; Size=2500; Rec=$false }
    @{ Alias='Lubuntu 24.04 LTS   - LXQt';           Cat='Linux / Ubuntu flavors'; Size=3000; Rec=$false }
    @{ Alias='Lubuntu 22.04 LTS   - LXQt';           Cat='Linux / Ubuntu flavors'; Size=2500; Rec=$false }
    @{ Alias='Lubuntu 20.04 LTS   - LXQt';           Cat='Linux / Ubuntu flavors'; Size=2000; Rec=$false }
    @{ Alias='Ubuntu MATE 24.04 LTS';                Cat='Linux / Ubuntu flavors'; Size=3500; Rec=$false }
    @{ Alias='Ubuntu MATE 22.04 LTS';                Cat='Linux / Ubuntu flavors'; Size=3000; Rec=$false }
    @{ Alias='Ubuntu MATE 20.04 LTS';                Cat='Linux / Ubuntu flavors'; Size=2500; Rec=$false }
    @{ Alias='Ubuntu Budgie 24.04 LTS';              Cat='Linux / Ubuntu flavors'; Size=4000; Rec=$false }
    @{ Alias='Ubuntu Budgie 22.04 LTS';              Cat='Linux / Ubuntu flavors'; Size=3500; Rec=$false }
    @{ Alias='Ubuntu Studio 24.04 LTS';              Cat='Linux / Ubuntu flavors'; Size=4500; Rec=$false }
    @{ Alias='Ubuntu Studio 22.04 LTS';              Cat='Linux / Ubuntu flavors'; Size=4000; Rec=$false }
    # ── Mint / MX / Pop ──
    @{ Alias='Linux Mint (latest)   - Cinnamon';     Cat='Linux / Other Debian';   Size=3000; Rec=$true  }
    @{ Alias='Linux Mint (latest)   - MATE';         Cat='Linux / Other Debian';   Size=2800; Rec=$false }
    @{ Alias='Linux Mint (latest)   - Xfce';         Cat='Linux / Other Debian';   Size=2500; Rec=$false }
    @{ Alias='MX Linux (latest)   - KDE';            Cat='Linux / Other Debian';   Size=3000; Rec=$false }
    @{ Alias='MX Linux (latest)   - Xfce';           Cat='Linux / Other Debian';   Size=1500; Rec=$false }
    @{ Alias='Pop!_OS 22.04   - Intel/AMD';          Cat='Linux / Other Debian';   Size=2500; Rec=$false }
    @{ Alias='Pop!_OS 22.04   - NVIDIA';             Cat='Linux / Other Debian';   Size=2600; Rec=$false }
    # ── RHEL family ──
    @{ Alias='Rocky Linux 9   - Minimal';            Cat='Linux / RHEL';     Size=1200; Rec=$true  }
    @{ Alias='Rocky Linux 8   - Minimal';            Cat='Linux / RHEL';     Size=1200; Rec=$false }
    @{ Alias='AlmaLinux 9   - Minimal';              Cat='Linux / RHEL';     Size=1200; Rec=$false }
    @{ Alias='AlmaLinux 8   - Minimal';              Cat='Linux / RHEL';     Size=1200; Rec=$false }
    @{ Alias='Fedora Workstation (latest)';          Cat='Linux / RHEL';     Size=2500; Rec=$true  }
    @{ Alias='CentOS Stream 9   - Boot';             Cat='Linux / RHEL';     Size=800;  Rec=$false }
    @{ Alias='CentOS Stream 10   - Boot';            Cat='Linux / RHEL';     Size=800;  Rec=$false }
    @{ Alias='Oracle Linux 9   - Boot';              Cat='Linux / RHEL';     Size=900;  Rec=$false }
    # ── Arch family ──
    @{ Alias='Arch Linux (latest)';                  Cat='Linux / Arch';     Size=1000; Rec=$true  }
    @{ Alias='EndeavourOS (latest)';                 Cat='Linux / Arch';     Size=3000; Rec=$false }
    @{ Alias='Manjaro   - KDE Plasma';               Cat='Linux / Arch';     Size=4000; Rec=$false }
    @{ Alias='Manjaro   - GNOME';                    Cat='Linux / Arch';     Size=4000; Rec=$false }
    @{ Alias='Manjaro   - Xfce';                     Cat='Linux / Arch';     Size=3500; Rec=$false }
    # ── Other Linux ──
    @{ Alias='openSUSE Leap (latest)';               Cat='Linux / Other';    Size=4500; Rec=$false }
    @{ Alias='openSUSE Tumbleweed (rolling)';        Cat='Linux / Other';    Size=4500; Rec=$false }
    # ── Pentest / Security ──
    @{ Alias='Kali Linux Live (manual: torrent only)'; Cat='Pentest / Security'; Size=4000; Rec=$false }
    @{ Alias='Kali Linux Installer (latest)';        Cat='Pentest / Security'; Size=3500; Rec=$true  }
    @{ Alias='Kali Purple SOC (latest)';             Cat='Pentest / Security'; Size=4000; Rec=$false }
    @{ Alias='Parrot Security OS (latest)';          Cat='Pentest / Security'; Size=3500; Rec=$true  }
    @{ Alias='Tails (latest)   - privacy/anon';      Cat='Pentest / Security'; Size=1500; Rec=$true  }
    # ── Sysadmin ──
    @{ Alias='Proxmox VE (latest)';                  Cat='Sysadmin';         Size=1200; Rec=$true  }
    @{ Alias='TrueNAS SCALE (latest)';               Cat='Sysadmin';         Size=1500; Rec=$false }
    @{ Alias='Clonezilla Live (latest)';             Cat='Sysadmin';         Size=500;  Rec=$true  }
    @{ Alias='GParted Live (latest)';                Cat='Sysadmin';         Size=700;  Rec=$true  }
    @{ Alias='Finnix (latest)';                      Cat='Sysadmin';         Size=500;  Rec=$false }
    # ── Rescue ──
    @{ Alias='SystemRescue (latest)';                Cat='Rescue';           Size=1000; Rec=$true  }
    @{ Alias="Hiren's BootCD PE";                    Cat='Rescue';           Size=2000; Rec=$true  }
    @{ Alias='MemTest86+ (latest)';                  Cat='Rescue';           Size=15;   Rec=$true  }
    # ── Windows ──
    @{ Alias='Windows 11  [Fido  - pick edition/lang]'; Cat='Windows';       Size=6000; Rec=$false }
    @{ Alias='Windows 11 IoT Enterprise LTSC 2024';  Cat='Windows';          Size=0;    Rec=$false }
    @{ Alias='Windows 10  [Fido  - pick edition/lang]'; Cat='Windows';       Size=5000; Rec=$false }
)

# ─── XAML ──────────────────────────────────────────────────────────────────
$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Spventoy" Height="820" Width="1100"
        WindowStartupLocation="CenterScreen"
        Background="#0a0612"
        FontFamily="Segoe UI" FontSize="13">
    <Window.Resources>
        <SolidColorBrush x:Key="BgDark"   Color="#0a0612"/>
        <SolidColorBrush x:Key="BgPanel" Color="#12082a"/>
        <SolidColorBrush x:Key="BgInput" Color="#1e0a3c"/>
        <SolidColorBrush x:Key="Border1" Color="#4c1d95"/>
        <SolidColorBrush x:Key="Accent"  Color="#7c3aed"/>
        <SolidColorBrush x:Key="TxtMain" Color="#e9d5ff"/>
        <SolidColorBrush x:Key="TxtDim"  Color="#a78bfa"/>
        <SolidColorBrush x:Key="TxtFaint" Color="#7c3aed"/>

        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
        </Style>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource BgInput}"/>
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border1}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="CaretBrush" Value="{StaticResource TxtMain}"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="{StaticResource BgInput}"/>
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border1}"/>
            <Setter Property="Padding" Value="6,4"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource BgInput}"/>
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border1}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#2d1157"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Accent}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{StaticResource Accent}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="22,8"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
        </Style>
        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
            <Setter Property="Margin" Value="0,0,16,0"/>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="{StaticResource TxtDim}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border1}"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
            <Setter Property="Padding" Value="10"/>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="{StaticResource BgPanel}"/>
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border1}"/>
        </Style>
    </Window.Resources>

    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- ── Header ───────────────────────────────────── -->
        <Border Grid.Row="0" Background="{StaticResource BgPanel}" BorderBrush="{StaticResource Border1}"
                BorderThickness="0,0,0,1" Padding="14,8" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock x:Name="TxtHeader" Text="SPVENTOY" FontSize="22" FontWeight="Bold"
                               Foreground="{StaticResource TxtMain}" Margin="0,0,0,2"/>
                    <TextBlock x:Name="TxtSubHeader" Text="MULTIBOOT  USB  BUILDER" FontSize="11"
                               Foreground="{StaticResource TxtDim}"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <RadioButton x:Name="RdoLangEs" Content="ES" IsChecked="True" GroupName="lang"/>
                    <RadioButton x:Name="RdoLangEn" Content="EN" GroupName="lang"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ── Body ──────────────────────────────────────── -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="380"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Form column -->
            <StackPanel Grid.Column="0" Margin="0,0,12,0">
                <GroupBox x:Name="GrpForm" Header="Build settings">
                    <StackPanel>
                        <TextBlock x:Name="LblTitle" Text="USB title" Margin="0,0,0,3"/>
                        <TextBox   x:Name="TxtTitle" Text="MYBOOT" Margin="0,0,0,12"/>

                        <TextBlock x:Name="LblMode" Text="Download mode" Margin="0,0,0,3"/>
                        <RadioButton x:Name="RdoDirect" GroupName="mode" IsChecked="True"
                                     Content="Direct to USB" Margin="0,2"/>
                        <RadioButton x:Name="RdoCache"  GroupName="mode"
                                     Content="Cache + copy" Margin="0,2,0,4"/>

                        <!-- Cache directory (visible only when Cache mode is selected) -->
                        <StackPanel x:Name="PnlCacheDir" Visibility="Collapsed" Margin="20,0,0,12">
                            <TextBlock x:Name="LblCacheDir" Text="Cache directory" Margin="0,0,0,3"
                                       FontSize="11" Foreground="{StaticResource TxtDim}"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="TxtCacheDir" Grid.Column="0"/>
                                <Button  x:Name="BtnBrowseCacheDir" Grid.Column="1" Content="..."
                                         Margin="6,0,0,0" Padding="10,4"/>
                            </Grid>
                        </StackPanel>

                        <TextBlock x:Name="LblDrive" Text="USB drive" Margin="0,0,0,3"/>
                        <Grid Margin="0,0,0,4">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <ComboBox x:Name="CmbDrive" Grid.Column="0"/>
                            <Button   x:Name="BtnRefresh" Grid.Column="1" Content="Refresh"
                                     Margin="6,0,0,0" Padding="10,4"/>
                        </Grid>
                        <Grid Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock x:Name="LblVentoyStatus" Grid.Column="0"
                                       Text="" VerticalAlignment="Center"
                                       Foreground="{StaticResource TxtDim}" FontSize="11"/>
                            <Button x:Name="BtnInstallVentoy" Grid.Column="1"
                                    Content="Install Ventoy" Padding="8,3" FontSize="11"
                                    Visibility="Collapsed"/>
                        </Grid>

                        <CheckBox x:Name="ChkPersist" Content="Create Kali persistence"
                                  IsChecked="False" Margin="0,4,0,6"/>
                        <Grid x:Name="GridPersist" IsEnabled="False">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="120"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock x:Name="LblPersistSize" Grid.Column="0"
                                       Text="Persistence size (MB)" VerticalAlignment="Center"/>
                            <TextBox   x:Name="TxtPersistSize" Grid.Column="1" Text="8192"/>
                        </Grid>
                    </StackPanel>
                </GroupBox>

                <GroupBox x:Name="GrpSummary" Header="Selection">
                    <TextBlock x:Name="TxtSummary" Text="0 selected, ~0 GB"
                               Foreground="{StaticResource TxtDim}"/>
                </GroupBox>
            </StackPanel>

            <!-- Right column: ISO list / log (toggled) -->
            <Grid Grid.Column="1">
                <GroupBox x:Name="GrpIsos" Header="ISO selection">
                    <DockPanel>
                        <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" Orientation="Horizontal">
                                <Button x:Name="BtnRecommended" Content="Recommended" Margin="0,0,8,0"/>
                                <Button x:Name="BtnAll"  Content="All"  Margin="0,0,8,0"/>
                                <Button x:Name="BtnNone" Content="None"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button x:Name="BtnAddCustom" Content="+ Add custom ISO" Margin="0,0,8,0"/>
                                <Button x:Name="BtnEditJson"  Content="Edit JSON"/>
                            </StackPanel>
                        </Grid>
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <ItemsControl x:Name="LstIsos"/>
                        </ScrollViewer>
                    </DockPanel>
                </GroupBox>

                <GroupBox x:Name="GrpLog" Header="Output" Visibility="Collapsed">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <ProgressBar x:Name="PrgOverall" Grid.Row="0" Height="8" Margin="0,0,0,8"
                                     Foreground="#7c3aed" Background="#1e0a3c" BorderBrush="#4c1d95"
                                     IsIndeterminate="True"/>
                        <TextBox x:Name="TxtLog" Grid.Row="1"
                                 Background="#0a0612" Foreground="#c4b5fd"
                                 BorderBrush="{StaticResource Border1}" BorderThickness="1"
                                 FontFamily="Consolas" FontSize="12"
                                 IsReadOnly="True" TextWrapping="NoWrap"
                                 VerticalScrollBarVisibility="Auto"
                                 HorizontalScrollBarVisibility="Auto"/>
                    </Grid>
                </GroupBox>
            </Grid>
        </Grid>

        <!-- ── Footer ───────────────────────────────────── -->
        <Border Grid.Row="2" Background="{StaticResource BgPanel}" BorderBrush="{StaticResource Border1}"
                BorderThickness="0,1,0,0" Padding="14,10" Margin="0,10,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="TxtStatus" Grid.Column="0" Text="Ready"
                           Foreground="{StaticResource TxtDim}" VerticalAlignment="Center"/>
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button x:Name="BtnStop"  Content="Stop"  IsEnabled="False" Margin="0,0,8,0"/>
                    <Button x:Name="BtnStart" Content="Start build" Style="{StaticResource PrimaryButton}"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

# ─── Load XAML ────────────────────────────────────────────────────────────
[xml]$xaml = $xamlText
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

function Find($n) { $window.FindName($n) }

# Bind controls to vars
$txtHeader      = Find 'TxtHeader'
$txtSubHeader   = Find 'TxtSubHeader'
$rdoLangEs      = Find 'RdoLangEs'
$rdoLangEn      = Find 'RdoLangEn'
$grpForm        = Find 'GrpForm'
$grpSummary     = Find 'GrpSummary'
$grpIsos        = Find 'GrpIsos'
$grpLog         = Find 'GrpLog'
$lblTitle       = Find 'LblTitle'
$txtTitle       = Find 'TxtTitle'
$lblMode        = Find 'LblMode'
$rdoDirect      = Find 'RdoDirect'
$rdoCache       = Find 'RdoCache'
$pnlCacheDir    = Find 'PnlCacheDir'
$lblCacheDir    = Find 'LblCacheDir'
$txtCacheDir    = Find 'TxtCacheDir'
$btnBrowseCacheDir = Find 'BtnBrowseCacheDir'
$lblDrive       = Find 'LblDrive'
$cmbDrive       = Find 'CmbDrive'
$btnRefresh     = Find 'BtnRefresh'
$lblVentoyStatus = Find 'LblVentoyStatus'
$btnInstallVentoy = Find 'BtnInstallVentoy'
$chkPersist     = Find 'ChkPersist'
$gridPersist    = Find 'GridPersist'
$lblPersistSize = Find 'LblPersistSize'
$txtPersistSize = Find 'TxtPersistSize'
$lstIsos        = Find 'LstIsos'
$btnRecommended = Find 'BtnRecommended'
$btnAll         = Find 'BtnAll'
$btnNone        = Find 'BtnNone'
$btnAddCustom   = Find 'BtnAddCustom'
$btnEditJson    = Find 'BtnEditJson'
$txtSummary     = Find 'TxtSummary'
$btnStart       = Find 'BtnStart'
$btnStop        = Find 'BtnStop'
$txtStatus      = Find 'TxtStatus'
$txtLog         = Find 'TxtLog'
$prgOverall     = Find 'PrgOverall'

# ─── ISO list rendering ────────────────────────────────────────────────────
$script:IsoCheckboxes = @()
$script:LocalPaths    = @{}   # alias → local path

function Pick-LocalIsoFile {
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    $ofd = [Microsoft.Win32.OpenFileDialog]::new()
    $ofd.Filter = 'ISO files (*.iso;*.img)|*.iso;*.img|All files (*.*)|*.*'
    $ofd.Title  = 'Select local ISO file'
    if ($ofd.ShowDialog($window)) { return $ofd.FileName }
    return $null
}

function Update-RowLocalState {
    param($Btn, $AliasLabel, $Alias)
    $path = $script:LocalPaths[$Alias]
    if ($path) {
        $name = [System.IO.Path]::GetFileName($path)
        if ($name.Length -gt 24) { $name = $name.Substring(0, 22) + '..' }
        $Btn.Content  = "OK $name"
        $Btn.ToolTip  = $path
        $Btn.Foreground = $window.FindResource('Accent')
        if ($AliasLabel -isnot [string]) {
            $AliasLabel.FontStyle = [Windows.FontStyles]::Italic
        }
    } else {
        $Btn.Content    = (L 'BtnUseLocal')
        $Btn.ToolTip    = (L 'TipUseLocal')
        $Btn.Foreground = $window.FindResource('TxtMain')
        if ($AliasLabel -isnot [string]) {
            $AliasLabel.FontStyle = [Windows.FontStyles]::Normal
        }
    }
}

function Format-Size([int]$mb) {
    if ($mb -le 0) { return 'manual' }
    if ($mb -ge 1024) { return ('~{0:N1} GB' -f ($mb / 1024.0)) }
    return ("~$mb MB")
}

function Update-Summary {
    $count = 0; $sumMb = 0
    foreach ($cb in $script:IsoCheckboxes) {
        if ($cb.IsChecked) {
            $count++
            $sumMb += [int]$cb.Tag.Size
        }
    }
    $gb = [Math]::Round($sumMb / 1024.0, 1)
    $txtSummary.Text = (L 'SelectedSummary') -f $count, $gb
}

$script:CustomJsonPath = Join-Path $script:AppRoot 'custom-isos.json'

function Load-CustomIsos {
    # Read custom-isos.json into $script:ISO_CATALOG entries (Cat='Custom').
    # Skips the example placeholder entry from the bundled JSON.
    if (-not (Test-Path $script:CustomJsonPath)) { return @() }
    try {
        $raw = Get-Content -Raw -Path $script:CustomJsonPath -ErrorAction Stop
        $arr = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch { return @() }
    $out = @()
    foreach ($e in $arr) {
        if (-not $e) { continue }
        if ($e.Urls -and $e.Urls.Count -gt 0 -and ($e.Urls[0] -like 'https://example.com/*')) {
            continue   # example placeholder, ignore
        }
        $out += @{
            Alias = [string]$e.Alias
            Cat   = (L 'CatCustom')
            Size  = if ($e.SizeMB) { [int]$e.SizeMB } else { 0 }
            Rec   = $false
            IsCustom = $true
            Name     = [string]$e.Name
            Folder   = if ($e.Folder) { [string]$e.Folder } else { 'Custom' }
            Urls     = @($e.Urls)
        }
    }
    return $out
}

function Save-CustomIsos([object[]]$entries) {
    # Persist the raw entries (one per array element) back to custom-isos.json.
    # We preserve the .ps1-friendly schema: Name, Alias, Folder, SizeMB, Urls.
    $arr = @()
    foreach ($e in $entries) {
        $arr += [pscustomobject]@{
            Name   = $e.Name
            Alias  = $e.Alias
            Folder = if ($e.Folder) { $e.Folder } else { 'Custom' }
            SizeMB = [int]$e.Size
            Urls   = @($e.Urls)
        }
    }
    $json = $arr | ConvertTo-Json -Depth 6
    if (-not $json.StartsWith('[')) { $json = '[' + $json + ']' }   # single-element edge case
    Set-Content -Path $script:CustomJsonPath -Value $json -Encoding UTF8
}

function Show-AddCustomIsoDialog {
    $dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Add custom ISO" Height="480" Width="540"
        WindowStartupLocation="CenterOwner"
        Background="#0a0612"
        FontFamily="Segoe UI" FontSize="13"
        ResizeMode="NoResize">
    <Window.Resources>
        <SolidColorBrush x:Key="BgInput" Color="#1e0a3c"/>
        <SolidColorBrush x:Key="Border1" Color="#4c1d95"/>
        <SolidColorBrush x:Key="Accent"  Color="#7c3aed"/>
        <SolidColorBrush x:Key="TxtMain" Color="#e9d5ff"/>
        <SolidColorBrush x:Key="TxtDim"  Color="#a78bfa"/>
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource TxtMain}"/></Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource BgInput}"/>
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border1}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="CaretBrush" Value="{StaticResource TxtMain}"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource BgInput}"/>
            <Setter Property="Foreground" Value="{StaticResource TxtMain}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border1}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock x:Name="LblAlias"    Grid.Row="0" Text="Alias"    Margin="0,0,0,3"/>
        <TextBox   x:Name="TxtAlias"    Grid.Row="1" Margin="0,0,0,8"/>
        <TextBlock x:Name="LblFileName" Grid.Row="2" Text="File"     Margin="0,0,0,3"/>
        <TextBox   x:Name="TxtFileName" Grid.Row="3" Margin="0,0,0,8"/>
        <Grid Grid.Row="4" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="120"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,8,0">
                <TextBlock x:Name="LblFolder" Text="Folder" Margin="0,0,0,3"/>
                <TextBox x:Name="TxtFolder" Text="Custom"/>
            </StackPanel>
            <StackPanel Grid.Column="1">
                <TextBlock x:Name="LblSize" Text="Size MB" Margin="0,0,0,3"/>
                <TextBox x:Name="TxtSize"/>
            </StackPanel>
        </Grid>
        <TextBlock x:Name="LblUrls" Grid.Row="5" Text="URLs"    Margin="0,0,0,3"/>
        <TextBox   x:Name="TxtUrls" Grid.Row="8"
                   AcceptsReturn="True" TextWrapping="NoWrap"
                   VerticalScrollBarVisibility="Auto"
                   HorizontalScrollBarVisibility="Auto"
                   MinHeight="100"/>
        <StackPanel Grid.Row="9" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="BtnDlgCancel" Content="Cancel" Margin="0,0,8,0"/>
            <Button x:Name="BtnDlgAdd"    Content="Add"/>
        </StackPanel>
    </Grid>
</Window>
'@
    [xml]$dx = $dlgXaml
    $dr = [System.Xml.XmlNodeReader]::new($dx)
    $dlg = [Windows.Markup.XamlReader]::Load($dr)
    $dlg.Owner = $window
    $dlg.Title = (L 'DlgAddTitle')
    $dlg.FindName('LblAlias').Text    = L 'DlgAlias'
    $dlg.FindName('LblFileName').Text = L 'DlgFileName'
    $dlg.FindName('LblFolder').Text   = L 'DlgFolder'
    $dlg.FindName('LblSize').Text     = L 'DlgSize'
    $dlg.FindName('LblUrls').Text     = L 'DlgUrls'
    $dlg.FindName('BtnDlgCancel').Content = L 'DlgCancel'
    $dlg.FindName('BtnDlgAdd').Content    = L 'DlgAdd'

    $script:DlgResult = $null
    $dlg.FindName('BtnDlgCancel').Add_Click({ $dlg.Close() })
    $dlg.FindName('BtnDlgAdd').Add_Click({
        $alias    = $dlg.FindName('TxtAlias').Text.Trim()
        $fileName = $dlg.FindName('TxtFileName').Text.Trim()
        $folder   = $dlg.FindName('TxtFolder').Text.Trim()
        $sizeText = $dlg.FindName('TxtSize').Text.Trim()
        $urlsText = $dlg.FindName('TxtUrls').Text
        $urls = @($urlsText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -match '^https?://' })

        $size = 0
        [void][int]::TryParse($sizeText, [ref]$size)

        if (-not $alias -or -not $fileName -or $size -le 0 -or $urls.Count -eq 0) {
            [System.Windows.MessageBox]::Show((L 'ErrCustomFields'), 'Spventoy', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $folder) { $folder = 'Custom' }
        $script:DlgResult = @{
            Alias    = $alias
            Name     = $fileName
            Folder   = $folder
            Size     = $size
            Urls     = $urls
            Cat      = (L 'CatCustom')
            Rec      = $false
            IsCustom = $true
        }
        $dlg.Close()
    })

    [void]$dlg.ShowDialog()
    return $script:DlgResult
}

function Add-CustomIso {
    $entry = Show-AddCustomIsoDialog
    if (-not $entry) { return }

    # Append to in-memory catalog and persist to JSON
    $script:ISO_CATALOG = $script:ISO_CATALOG + $entry

    $existing = @($script:ISO_CATALOG | Where-Object { $_.IsCustom })
    Save-CustomIsos -entries $existing

    # Rebuild the ISO list and pre-check the new entry
    Build-IsoList
    foreach ($cb in $script:IsoCheckboxes) {
        if ($cb.Tag.Alias -eq $entry.Alias) { $cb.IsChecked = $true; break }
    }
    Update-Summary
}

function Open-CustomJsonInEditor {
    if (-not (Test-Path $script:CustomJsonPath)) {
        Set-Content -Path $script:CustomJsonPath -Value '[]' -Encoding UTF8
    }
    Start-Process notepad.exe $script:CustomJsonPath
}

function Build-IsoList {
    $lstIsos.Items.Clear()
    $script:IsoCheckboxes = @()
    $script:IsoExpanders  = @()

    $grouped = $script:ISO_CATALOG | Group-Object { $_.Cat }
    foreach ($g in $grouped) {
        $exp = New-Object Windows.Controls.Expander
        $exp.Header     = "$($g.Name)  ($($g.Count))"
        $exp.Foreground = $window.FindResource('TxtDim')
        $exp.FontWeight = 'SemiBold'
        $exp.IsExpanded = $false
        $exp.Margin     = '0,2,0,2'

        $catBody = New-Object Windows.Controls.StackPanel
        $catBody.Margin = '12,4,0,4'

        foreach ($iso in $g.Group) {
            # Row layout: [checkbox + alias + size] [spacer] [Use-local button]
            $row = New-Object Windows.Controls.Grid
            $row.Margin = '0,2,0,2'
            $col1 = New-Object Windows.Controls.ColumnDefinition; $col1.Width = '*'
            $col2 = New-Object Windows.Controls.ColumnDefinition; $col2.Width = 'Auto'
            [void]$row.ColumnDefinitions.Add($col1)
            [void]$row.ColumnDefinitions.Add($col2)

            $cb = New-Object Windows.Controls.CheckBox
            $cb.Tag = $iso
            [Windows.Controls.Grid]::SetColumn($cb, 0)

            $sp = New-Object Windows.Controls.StackPanel
            $sp.Orientation = 'Horizontal'

            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text = $iso.Alias
            $tb.Width = 360

            $sz = New-Object Windows.Controls.TextBlock
            $sz.Text = (Format-Size $iso.Size)
            $sz.Foreground = $window.FindResource('TxtDim')
            $sz.FontSize = 11
            $sz.VerticalAlignment = 'Center'

            [void]$sp.Children.Add($tb)
            [void]$sp.Children.Add($sz)
            $cb.Content = $sp
            $cb.Add_Checked({ Update-Summary })
            $cb.Add_Unchecked({ Update-Summary })

            # Use-local button (right-aligned)
            $btnLocal = New-Object Windows.Controls.Button
            $btnLocal.Padding = '8,2'
            $btnLocal.Margin  = '8,0,8,0'
            $btnLocal.FontSize = 11
            $btnLocal.Tag = @{ Iso = $iso; CheckBox = $cb; Label = $tb }
            [Windows.Controls.Grid]::SetColumn($btnLocal, 1)

            $btnLocal.Add_Click({
                param($s, $e)
                $tag = $s.Tag
                $picked = Pick-LocalIsoFile
                if ($picked) {
                    $script:LocalPaths[$tag.Iso.Alias] = $picked
                    $tag.CheckBox.IsChecked = $true   # auto-select once a local file is provided
                    Update-RowLocalState -Btn $s -AliasLabel $tag.Label -Alias $tag.Iso.Alias
                }
            })

            # Right-click to clear
            $cm = New-Object Windows.Controls.ContextMenu
            $miClear = New-Object Windows.Controls.MenuItem
            $miClear.Header = (L 'BtnClearLocal')
            $miClear.Tag = $btnLocal
            $miClear.Add_Click({
                param($s, $e)
                $btn = $s.Tag
                $tag = $btn.Tag
                $script:LocalPaths.Remove($tag.Iso.Alias)
                Update-RowLocalState -Btn $btn -AliasLabel $tag.Label -Alias $tag.Iso.Alias
            })
            [void]$cm.Items.Add($miClear)
            $btnLocal.ContextMenu = $cm

            Update-RowLocalState -Btn $btnLocal -AliasLabel $tb -Alias $iso.Alias

            [void]$row.Children.Add($cb)
            [void]$row.Children.Add($btnLocal)

            [void]$catBody.Children.Add($row)
            $script:IsoCheckboxes += $cb
        }
        $exp.Content = $catBody
        [void]$lstIsos.Items.Add($exp)
        $script:IsoExpanders += $exp
    }
    Update-Summary
}

# ─── i18n apply ────────────────────────────────────────────────────────────
function Apply-Lang {
    $window.Title       = L 'WindowTitle'
    $txtHeader.Text     = L 'Header'
    $txtSubHeader.Text  = L 'SubHeader'
    $grpForm.Header     = L 'SectionForm'
    $grpIsos.Header     = L 'SectionIsos'
    $grpLog.Header      = L 'SectionLog'
    $grpSummary.Header  = (L 'SelectedSummary') -split ',' | Select-Object -First 1
    $lblTitle.Text      = L 'LblTitle'
    $lblMode.Text       = L 'LblMode'
    $rdoDirect.Content  = L 'ModeDirect'
    $rdoCache.Content   = L 'ModeCache'
    $lblDrive.Text      = L 'LblDrive'
    $btnRefresh.Content = L 'BtnRefresh'
    $chkPersist.Content = L 'LblPersist'
    $lblPersistSize.Text= L 'LblPersistSize'
    $btnRecommended.Content = L 'BtnRecommended'
    $btnAll.Content     = L 'BtnAll'
    $btnNone.Content    = L 'BtnNone'
    $btnInstallVentoy.Content = L 'BtnInstallVentoy'
    $lblCacheDir.Text         = L 'LblCacheDir'
    $btnBrowseCacheDir.Content = '...'
    Update-VentoyStatus
    $btnStart.Content   = L 'BtnStart'
    $btnStop.Content    = L 'BtnStop'
    $txtStatus.Text     = L 'StatusReady'
    Update-Summary
}

# ─── USB drive enumeration ────────────────────────────────────────────────
function Refresh-Drives {
    $cmbDrive.Items.Clear()
    try {
        $vols = Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Removable' }
        foreach ($v in $vols) {
            $label = $v.FileSystemLabel; if (-not $label) { $label = '(no label)' }
            $sizeGb = if ($v.Size -gt 0) { [Math]::Round($v.Size / 1GB, 1) } else { 0 }
            $item = "$($v.DriveLetter):  $label  ($sizeGb GB)"
            [void]$cmbDrive.Items.Add($item)
        }
        # If a Ventoy-labeled drive exists, preselect it
        $idx = -1
        for ($i=0; $i -lt $cmbDrive.Items.Count; $i++) {
            if ($cmbDrive.Items[$i] -match 'Ventoy|VENTOY') { $idx = $i; break }
        }
        if ($idx -ge 0) { $cmbDrive.SelectedIndex = $idx }
        elseif ($cmbDrive.Items.Count -gt 0) { $cmbDrive.SelectedIndex = 0 }
    } catch {}
}

function Get-SelectedDriveLetter {
    if (-not $cmbDrive.SelectedItem) { return $null }
    $m = [regex]::Match($cmbDrive.SelectedItem, '^([A-Z]):')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Test-VentoyOnDrive([string]$letter) {
    if (-not $letter) { return $false }
    try {
        $vol = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
        if ($vol -and ($vol.FileSystemLabel -in @('Ventoy', 'VENTOY'))) { return $true }
        # Also check for the user-content folder which exists on configured Ventoy USBs
        if (Test-Path "${letter}:\ventoy") { return $true }
    } catch {}
    return $false
}

function Update-VentoyStatus {
    $letter = Get-SelectedDriveLetter
    if (-not $letter) {
        $lblVentoyStatus.Text = ''
        $btnInstallVentoy.Visibility = 'Collapsed'
        return
    }
    if (Test-VentoyOnDrive $letter) {
        $lblVentoyStatus.Text = (L 'VentoyInstalled')
        $lblVentoyStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $btnInstallVentoy.Visibility = 'Collapsed'
    } else {
        $lblVentoyStatus.Text = (L 'VentoyNotInstalled')
        $lblVentoyStatus.Foreground = [System.Windows.Media.Brushes]::Goldenrod
        $btnInstallVentoy.Visibility = 'Visible'
    }
}

function Install-VentoyOnDrive {
    $letter = Get-SelectedDriveLetter
    if (-not $letter) {
        [System.Windows.MessageBox]::Show((L 'ErrDrive'), 'Spventoy', 'OK', 'Error') | Out-Null
        return
    }
    $r = [System.Windows.MessageBox]::Show(((L 'ConfirmInstallVentoy') -f "${letter}:"), 'Spventoy', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }

    # Pull the Ventoy installer URL straight from the official latest release
    $ventoyZip = $null
    $tempDir   = Join-Path $env:TEMP "spventoy_ventoy_$([Guid]::NewGuid().ToString('N'))"
    [void](New-Item -ItemType Directory -Path $tempDir -Force)
    try {
        Add-Type -AssemblyName System.Net.Http
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromMinutes(2)
        [void]$client.DefaultRequestHeaders.UserAgent.TryParseAdd('Spventoy/1.0')

        $apiUrl = 'https://api.github.com/repos/ventoy/Ventoy/releases/latest'
        $rel    = $client.GetStringAsync($apiUrl).GetAwaiter().GetResult() | ConvertFrom-Json
        $asset  = $rel.assets | Where-Object { $_.name -match 'windows\.zip$' } | Select-Object -First 1
        if (-not $asset) { throw 'Ventoy windows asset not found' }

        $ventoyZip = Join-Path $tempDir $asset.name
        $bytes = $client.GetByteArrayAsync($asset.browser_download_url).GetAwaiter().GetResult()
        [System.IO.File]::WriteAllBytes($ventoyZip, $bytes)
        $client.Dispose()

        Expand-Archive -Path $ventoyZip -DestinationPath $tempDir -Force
        $exe = Get-ChildItem -Path $tempDir -Recurse -Filter 'Ventoy2Disk.exe' -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName
        if (-not $exe) { throw 'Ventoy2Disk.exe not found in zip' }

        Start-Process -FilePath $exe -Wait
        # After the user closes Ventoy2Disk, refresh
        Refresh-Drives
        Update-VentoyStatus
    } catch {
        [System.Windows.MessageBox]::Show("Install Ventoy failed: $($_.Exception.Message)", 'Spventoy', 'OK', 'Error') | Out-Null
    } finally {
        try { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}

# ─── Quick-select handlers ────────────────────────────────────────────────
function Expand-AllCategories([bool]$open = $true) {
    foreach ($exp in $script:IsoExpanders) { $exp.IsExpanded = $open }
}
function Set-AllChecked([bool]$v) {
    foreach ($cb in $script:IsoCheckboxes) { $cb.IsChecked = $v }
    Expand-AllCategories $v
    Update-Summary
}
function Set-Recommended {
    foreach ($cb in $script:IsoCheckboxes) { $cb.IsChecked = [bool]$cb.Tag.Rec }
    Expand-AllCategories $true
    Update-Summary
}

# ─── Admin check ──────────────────────────────────────────────────────────
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ─── Build subprocess (file-based polling, no async events) ────────────────
$script:BuildProcess = $null
$script:BuildTimer   = $null
$script:BuildLogOut  = $null
$script:BuildLogErr  = $null
$script:BuildOutPos  = 0L
$script:BuildErrPos  = 0L

function Append-Log {
    param([string]$line)
    if ($null -eq $line) { return }
    try {
        $script:txtLog.AppendText($line + "`r`n")
        $script:txtLog.ScrollToEnd()
    } catch {}
}

function Read-NewLogContent([string]$path, [ref]$offset) {
    if (-not (Test-Path $path)) { return '' }
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $size = $fs.Length
            if ($size -le $offset.Value) { return '' }
            $fs.Position = $offset.Value
            $sr = [System.IO.StreamReader]::new($fs)
            $content = $sr.ReadToEnd()
            $offset.Value = $size
            return $content
        } finally { $fs.Close() }
    } catch { return '' }
}

function Finish-Build([int]$code) {
    if ($script:BuildTimer) {
        try { $script:BuildTimer.Stop() } catch {}
        $script:BuildTimer = $null
    }
    foreach ($f in @($script:BuildLogOut, $script:BuildLogErr)) {
        if ($f -and (Test-Path $f)) {
            try { Remove-Item $f -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    try {
        $script:btnStart.IsEnabled = $true
        $script:btnStop.IsEnabled  = $false
        $script:cmbDrive.IsEnabled = $true
        $script:txtTitle.IsEnabled = $true
        $script:rdoDirect.IsEnabled  = $true
        $script:rdoCache.IsEnabled   = $true
        $script:chkPersist.IsEnabled = $true
        $script:btnRecommended.IsEnabled = $true
        $script:btnAll.IsEnabled  = $true
        $script:btnNone.IsEnabled = $true
        $script:prgOverall.IsIndeterminate = $false
        $script:prgOverall.Value = if ($code -eq 0) { 100 } else { 0 }
        $script:txtStatus.Text = if ($code -eq 0) { L 'StatusDone' } elseif ($code -eq -1) { L 'StatusStopped' } else { (L 'StatusFailed') -f $code }
    } catch {}
}

function Start-Build {
    if ($script:BuildProcess -and -not $script:BuildProcess.HasExited) {
        [System.Windows.MessageBox]::Show((L 'WarnRunning'), 'Spventoy', 'OK', 'Warning') | Out-Null
        return
    }

    # Validate
    $title = $txtTitle.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($title)) {
        [System.Windows.MessageBox]::Show((L 'ErrTitle'), 'Spventoy', 'OK', 'Error') | Out-Null
        return
    }
    $drive = Get-SelectedDriveLetter
    if (-not $drive) {
        [System.Windows.MessageBox]::Show((L 'ErrDrive'), 'Spventoy', 'OK', 'Error') | Out-Null
        return
    }
    $aliases = @()
    foreach ($cb in $script:IsoCheckboxes) {
        if ($cb.IsChecked) { $aliases += $cb.Tag.Alias }
    }
    if ($aliases.Count -eq 0) {
        [System.Windows.MessageBox]::Show((L 'ErrNoIsos'), 'Spventoy', 'OK', 'Error') | Out-Null
        return
    }

    # Build args
    $scriptPath = Join-Path $script:AppRoot 'Build-MultibootUSB.ps1'
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.MessageBox]::Show("Build-MultibootUSB.ps1 not found in $script:AppRoot", 'Spventoy', 'OK', 'Error') | Out-Null
        return
    }

    # Write the alias list to a temp file (one per line) — passing a string[]
    # via -File ARGV is unreliable with spaces / quotes / special chars.
    $aliasFile = Join-Path $env:TEMP "spventoy_aliases_$([Guid]::NewGuid().ToString('N')).txt"
    Set-Content -LiteralPath $aliasFile -Value $aliases -Encoding UTF8

    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File',  $scriptPath,
        '-NonInteractive',
        '-Language', $script:Lang,
        '-Title',   $title,
        '-UsbDriveLetter', $drive,
        '-SelectedIsoAliasesFile', $aliasFile
    )
    if ($rdoDirect.IsChecked) {
        $argList += '-DirectToUSB'
    } else {
        $argList += '-UseCache'
        $cacheDir = $txtCacheDir.Text.Trim()
        if ($cacheDir) { $argList += @('-DownloadDir', $cacheDir) }
    }
    if (-not $chkPersist.IsChecked) { $argList += '-SkipPersistence' }
    # If Ventoy is already on the selected drive, skip the install step entirely
    if (Test-VentoyOnDrive $drive) { $argList += '-SkipVentoyInstall' }
    else {
        $sz = 0
        if ([int]::TryParse($txtPersistSize.Text.Trim(), [ref]$sz) -and $sz -gt 0) {
            $argList += @('-PersistenceSizeMB', $sz)
        }
    }

    # If user mapped any ISOs to local files, write a temp JSON and pass it
    if ($script:LocalPaths.Count -gt 0) {
        $localTmp = Join-Path $env:TEMP "spventoy_localpaths_$([Guid]::NewGuid().ToString('N')).json"
        $obj = New-Object PSObject
        foreach ($k in $script:LocalPaths.Keys) {
            $obj | Add-Member -NotePropertyName $k -NotePropertyValue $script:LocalPaths[$k]
        }
        ($obj | ConvertTo-Json -Depth 4) | Set-Content -Path $localTmp -Encoding UTF8
        $argList += @('-LocalIsoPathsFile', $localTmp)
    }

    # Switch UI to "running" state
    $grpIsos.Visibility   = 'Collapsed'
    $grpLog.Visibility    = 'Visible'
    $txtLog.Clear()
    $btnStart.IsEnabled   = $false
    $btnStop.IsEnabled    = $true
    $cmbDrive.IsEnabled   = $false
    $txtTitle.IsEnabled   = $false
    $rdoDirect.IsEnabled  = $false
    $rdoCache.IsEnabled   = $false
    $chkPersist.IsEnabled = $false
    $btnRecommended.IsEnabled = $false
    $btnAll.IsEnabled     = $false
    $btnNone.IsEnabled    = $false
    $prgOverall.IsIndeterminate = $true
    $txtStatus.Text = L 'StatusRunning'

    Append-Log "Spventoy GUI launching build..."
    Append-Log "  Title:    $title"
    Append-Log "  Drive:    $drive`:"
    Append-Log "  Mode:     $(if ($rdoDirect.IsChecked) {'Direct to USB'} else {'Cache + copy'})"
    Append-Log "  ISOs:     $($aliases.Count) selected"
    Append-Log "  Command:  pwsh $($argList -join ' ')"
    Append-Log ""

    # Choose pwsh.exe (PS7) if available, else powershell.exe
    $exe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)
    if ($exe) { $exe = $exe.Source } else { $exe = 'powershell.exe' }

    # Redirect stdout/stderr to temp files; we poll them from a UI-thread timer
    # so we never have async events / cross-thread Dispatcher.Invoke calls.
    $guid = [Guid]::NewGuid().ToString('N')
    $script:BuildLogOut = Join-Path $env:TEMP "spventoy_build_$guid.out.log"
    $script:BuildLogErr = Join-Path $env:TEMP "spventoy_build_$guid.err.log"
    $script:BuildOutPos = 0L
    $script:BuildErrPos = 0L

    try {
        $proc = Start-Process -FilePath $exe -ArgumentList $argList `
            -RedirectStandardOutput $script:BuildLogOut `
            -RedirectStandardError  $script:BuildLogErr `
            -WorkingDirectory $script:AppRoot `
            -WindowStyle Hidden -PassThru
    } catch {
        Append-Log "[ERR] Failed to start subprocess: $($_.Exception.Message)"
        Finish-Build -1
        return
    }
    $script:BuildProcess = $proc

    $script:BuildTimer = New-Object Windows.Threading.DispatcherTimer
    $script:BuildTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:BuildTimer.Add_Tick({
        try {
            $oRef = [ref]$script:BuildOutPos
            $eRef = [ref]$script:BuildErrPos
            $oNew = Read-NewLogContent $script:BuildLogOut $oRef
            $eNew = Read-NewLogContent $script:BuildLogErr $eRef
            $script:BuildOutPos = $oRef.Value
            $script:BuildErrPos = $eRef.Value
            if ($oNew) { $script:txtLog.AppendText($oNew); $script:txtLog.ScrollToEnd() }
            if ($eNew) { $script:txtLog.AppendText('[ERR] ' + $eNew); $script:txtLog.ScrollToEnd() }

            if ($script:BuildProcess -and $script:BuildProcess.HasExited) {
                # Drain any remaining output
                $oNew = Read-NewLogContent $script:BuildLogOut ([ref]$script:BuildOutPos)
                $eNew = Read-NewLogContent $script:BuildLogErr ([ref]$script:BuildErrPos)
                if ($oNew) { $script:txtLog.AppendText($oNew); $script:txtLog.ScrollToEnd() }
                if ($eNew) { $script:txtLog.AppendText('[ERR] ' + $eNew); $script:txtLog.ScrollToEnd() }

                $code = try { $script:BuildProcess.ExitCode } catch { -1 }
                Finish-Build $code
            }
        } catch {
            Append-Log "[GUI] Timer error: $($_.Exception.Message)"
        }
    })
    $script:BuildTimer.Start()
}

function Stop-Build {
    if (-not $script:BuildProcess -or $script:BuildProcess.HasExited) { return }
    $r = [System.Windows.MessageBox]::Show((L 'ConfirmStop'), 'Spventoy', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }
    try { $script:BuildProcess.Kill($true) } catch {}
    # Timer will detect HasExited on next tick and call Finish-Build
}

# ─── Wire up events ───────────────────────────────────────────────────────
$btnRefresh.Add_Click({ Refresh-Drives; Update-VentoyStatus })
$cmbDrive.Add_SelectionChanged({ Update-VentoyStatus })
$btnInstallVentoy.Add_Click({ Install-VentoyOnDrive })
$btnRecommended.Add_Click({ Set-Recommended })
$btnAll.Add_Click({ Set-AllChecked $true })
$btnNone.Add_Click({ Set-AllChecked $false })
$btnAddCustom.Add_Click({ Add-CustomIso })
$btnEditJson.Add_Click({ Open-CustomJsonInEditor })
$btnStart.Add_Click({ Start-Build })
$btnStop.Add_Click({ Stop-Build })

$chkPersist.Add_Checked({   $gridPersist.IsEnabled = $true })
$chkPersist.Add_Unchecked({ $gridPersist.IsEnabled = $false })

# Toggle the cache-dir UI when the user picks Cache mode. Also seed the field
# with a sensible default the first time it's shown.
$rdoCache.Add_Checked({
    $pnlCacheDir.Visibility = 'Visible'
    if ([string]::IsNullOrWhiteSpace($txtCacheDir.Text)) {
        $title = $txtTitle.Text.Trim()
        if (-not $title) { $title = 'MYBOOT' }
        $txtCacheDir.Text = Join-Path $env:USERPROFILE "${title}_cache"
    }
})
$rdoDirect.Add_Checked({ $pnlCacheDir.Visibility = 'Collapsed' })

$btnBrowseCacheDir.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = 'Select cache directory for ISO downloads'
    if ($txtCacheDir.Text -and (Test-Path $txtCacheDir.Text -ErrorAction SilentlyContinue)) {
        $fbd.SelectedPath = $txtCacheDir.Text
    } else {
        $fbd.SelectedPath = $env:USERPROFILE
    }
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtCacheDir.Text = $fbd.SelectedPath
    }
})

function Switch-Language([string]$lang) {
    # Preserve check state across the rebuild
    $prevChecked = @{}
    foreach ($cb in $script:IsoCheckboxes) {
        if ($cb.IsChecked) { $prevChecked[$cb.Tag.Alias] = $true }
    }
    $script:Lang = $lang
    # Rewrite the 'Custom' category label on existing custom entries
    foreach ($iso in $script:ISO_CATALOG) {
        if ($iso.IsCustom) { $iso.Cat = (L 'CatCustom') }
    }
    Build-IsoList
    foreach ($cb in $script:IsoCheckboxes) {
        if ($prevChecked[$cb.Tag.Alias]) { $cb.IsChecked = $true }
    }
    Apply-Lang
    Update-Summary
}

$rdoLangEs.Add_Checked({ Switch-Language 'es' })
$rdoLangEn.Add_Checked({ Switch-Language 'en' })

$window.Add_Closing({
    if ($script:BuildProcess -and -not $script:BuildProcess.HasExited) {
        $r = [System.Windows.MessageBox]::Show((L 'ConfirmClose'), 'Spventoy', 'YesNo', 'Warning')
        if ($r -ne 'Yes') {
            $_.Cancel = $true
            return
        }
        try { $script:BuildProcess.Kill($true) } catch {}
    }
})

# ─── Initialise ───────────────────────────────────────────────────────────
# Load any custom ISOs from custom-isos.json and merge them into the catalog
$customIsos = Load-CustomIsos
if ($customIsos.Count -gt 0) {
    $script:ISO_CATALOG = $script:ISO_CATALOG + $customIsos
}

Build-IsoList
Set-Recommended
Refresh-Drives
Apply-Lang
Update-VentoyStatus

# Admin check (warn but don't block — user might want to test the GUI without writing a USB)
if (-not (Test-Admin)) {
    [System.Windows.MessageBox]::Show((L 'ErrNotAdmin'), 'Spventoy', 'OK', 'Warning') | Out-Null
}

# ─── Show ─────────────────────────────────────────────────────────────────
[void]$window.ShowDialog()
