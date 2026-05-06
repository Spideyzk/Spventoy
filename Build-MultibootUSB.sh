#!/usr/bin/env bash
# ============================================================
#  Build-MultibootUSB.sh  –  Multiboot USB Builder for Linux
#  Requires: bash 4+, curl, lsblk, sudo, tar, jq (optional)
# ============================================================

set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
E=$'\033'
RST="${E}[0m"
CY="${E}[38;5;51m"   BL="${E}[38;5;39m"  GR="${E}[38;5;82m"
YL="${E}[38;5;220m"  OR="${E}[38;5;208m" WH="${E}[38;5;231m"
GY="${E}[38;5;246m"  DM="${E}[38;5;243m" VD="${E}[38;5;240m"
BLD="${E}[1m"        BG_CUR="${E}[48;5;17m"  BG_SEC="${E}[48;5;18m"
BAR_ON="${E}[38;5;39m"  BAR_OFF="${E}[38;5;237m"

# ── Symbols ───────────────────────────────────────────────────────────────────
BLK=$'\xe2\x96\x88'   LGT=$'\xe2\x96\x91'   # █  ░  (block chars, safe in most terminals)
CHK="*"  CRC=" "  ARR_R=">"  ARR_D="v"  ARR_L="<"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()  { printf "     ${BL}[*]${RST} %s\n" "$*"; }
ok()    { printf "     ${GR}[OK]${RST} %s\n" "$*"; }
err()   { printf "     ${E}[38;5;196m[ERR]${RST} %s\n" "$*" >&2; }
warn()  { printf "     ${YL}[!]${RST} %s\n" "$*"; }
step()  { printf "\n  ${CY}${BLD}[*]${RST} ${WH}%s${RST}\n" "$*"; }

# strip ANSI codes to measure visual length
vlen() { printf '%s' "$1" | sed 's/\x1B\[[0-9;]*m//g' | wc -c; }

# pad/truncate a line to exactly W visible chars, then append RST + CRLF
wl() {
    local line="$1" W="$2"
    local vl; vl=$(vlen "$line")
    local pad=$(( W - vl ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%s%*s%s\r\n' "$line" "$pad" "" "$RST"
}

mkbar() {          # mkbar n total width  → prints bar string
    local n=$1 total=$2 bw=$3
    local f=0
    [[ $total -gt 0 ]] && f=$(( n * bw / total ))
    [[ $f -gt $bw ]] && f=$bw
    local e=$(( bw - f ))
    local filled="" empty=""
    [[ $f -gt 0 ]] && filled=$(printf "${BLK}%.0s" $(seq 1 $f))
    [[ $e -gt 0 ]] && empty=$(printf "${LGT}%.0s" $(seq 1 $e))
    printf '%s' "${BAR_ON}${filled}${BAR_OFF}${empty}${RST}"
}

# ── Parameters ────────────────────────────────────────────────────────────────
LANGUAGE=""  TITLE=""  DOWNLOAD_DIR=""
USB_MOUNT="" USB_DEVICE=""
SKIP_VENTOY=0  SKIP_PERSISTENCE=0  PERSISTENCE_MB=8192
USE_DIRECT=0  USE_CACHE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]
  -l en|es        UI language
  -t TITLE        USB label / boot menu title
  -d DIR          ISO download/cache directory (used for tooling even in direct mode)
  -m MOUNTPOINT   Ventoy USB mount point (e.g. /media/user/Ventoy)
  -D DEVICE       Block device for Ventoy install (e.g. /dev/sdb)
  -u              Direct-to-USB mode: download ISOs straight to the USB (faster)
  -c              Cache mode: download to cache then copy to USB (slower, reusable)
  -P              Skip Kali persistence partition
  -V              Skip Ventoy download/install
  -s SIZE_MB      Kali persistence size in MB (default: 8192)
  -h              Show this help

If neither -u nor -c is passed, the script asks interactively.
EOF
    exit 0
}

while getopts "l:t:d:m:D:ucPVs:h" opt 2>/dev/null; do
    case $opt in
        l) LANGUAGE="$OPTARG" ;;    t) TITLE="$OPTARG" ;;
        d) DOWNLOAD_DIR="$OPTARG" ;; m) USB_MOUNT="$OPTARG" ;;
        D) USB_DEVICE="$OPTARG" ;;  P) SKIP_PERSISTENCE=1 ;;
        V) SKIP_VENTOY=1 ;;         s) PERSISTENCE_MB="$OPTARG" ;;
        u) USE_DIRECT=1 ;;          c) USE_CACHE=1 ;;
        h) usage ;;
    esac
done

if [[ $USE_DIRECT -eq 1 && $USE_CACHE -eq 1 ]]; then
    echo "Cannot use both -u and -c. Pick one." >&2
    exit 1
fi

# ── URL Resolvers ─────────────────────────────────────────────────────────────

resolve_debian_urls() {        # de $1=flavor  $2=major(13)
    local flavor="${1:-gnome}" major="${2:-13}"
    local base_cur="https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid"
    local base_arc="https://cdimage.debian.org/cdimage/archive"
    if [[ "$major" == "13" ]]; then
        # current stable — filename uses actual version like 13.4.0
        local ver; ver=$(curl -fsSL --max-time 10 \
            "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/" 2>/dev/null \
            | grep -oP 'debian-live-\K[0-9.]+(?=-amd64)' | sort -V | tail -1)
        ver="${ver:-13.4.0}"
        echo "${base_cur}/debian-live-${ver}-amd64-${flavor}.iso"
    elif [[ "$major" == "12" ]]; then
        local ver="12.11.0"
        echo "${base_arc}/${ver}/live/amd64/debian-live-${ver}-amd64-${flavor}.iso"
        echo "${base_cur}/debian-live-${ver}-amd64-${flavor}.iso"
    else
        local ver="11.11.0"
        echo "${base_arc}/${ver}/live/amd64/debian-live-${ver}-amd64-${flavor}.iso"
    fi
}

resolve_ubuntu_urls() {        # $1=type(desktop|live-server)  $2=ver(24.04)
    local type="$1" ver="$2"
    local point="${ver}.1"
    local base="https://releases.ubuntu.com"
    echo "${base}/${ver}/ubuntu-${point}-${type}-amd64.iso"
    echo "${base}/${ver}/ubuntu-${ver}-${type}-amd64.iso"
}

resolve_ubuntu_flavor_urls() { # $1=slug  $2=ver
    local slug="$1" ver="$2"
    echo "https://cdimage.ubuntu.com/${slug}/releases/${ver}/release/${slug}-${ver}-desktop-amd64.iso"
}

resolve_kali_urls() {          # $1=variant(live-amd64)
    local variant="${1:-live-amd64}"
    local latest; latest=$(curl -fsSL --max-time 10 \
        "https://cdimage.kali.org/current/" 2>/dev/null \
        | grep -oP 'kali-linux-[0-9.]+(?=-'"${variant}"')' | sort -V | tail -1)
    local ver="${latest:-kali-linux-2025.1}"
    echo "https://cdimage.kali.org/current/${ver}-${variant}.iso"
    echo "https://kali.download/base-images/current/${ver}-${variant}.iso"
}

resolve_rocky_urls() {         # $1=major
    local major="${1:-9}"
    echo "https://download.rockylinux.org/pub/rocky/${major}/isos/x86_64/Rocky-${major}-latest-x86_64-minimal.iso"
    echo "https://mirror.23media.com/rockylinux/${major}/isos/x86_64/Rocky-${major}-latest-x86_64-minimal.iso"
}

resolve_fedora_urls() {
    local ver; ver=$(curl -fsSL --max-time 10 \
        "https://api.fedoraproject.org/bodhi/updates/?releases=F&status=stable&type=security&rows_per_page=1" \
        2>/dev/null | grep -oP '"version":"\K[0-9]+' | head -1)
    ver="${ver:-42}"
    echo "https://download.fedoraproject.org/pub/fedora/linux/releases/${ver}/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-${ver}-1.1.iso"
    echo "https://mirror.cov.ukservers.com/fedora/linux/releases/${ver}/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-${ver}-1.1.iso"
}

resolve_arch_urls() {
    echo "https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso"
    echo "https://mirrors.edge.kernel.org/archlinux/iso/latest/archlinux-x86_64.iso"
    echo "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"
}

resolve_proxmox_urls() {
    local ver; ver=$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/proxmox/pve-installer/releases/latest" 2>/dev/null \
        | grep -oP '"tag_name"\s*:\s*"v\K[0-9.-]+' | head -1)
    ver="${ver:-8.4-1}"
    echo "https://enterprise.proxmox.com/iso/proxmox-ve_${ver}.iso"
    echo "https://mirrors.apqa.cn/proxmox/iso/proxmox-ve_${ver}.iso"
}

resolve_truenas_urls() {
    local latest; latest=$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/truenas/truenas-installer/releases/latest" 2>/dev/null \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1)
    latest="${latest:-25.04}"
    echo "https://download.sys.truenas.net/TrueNAS-SCALE-${latest}/TrueNAS-SCALE-${latest}.iso"
}

resolve_clonezilla_urls() {
    local ver; ver=$(curl -fsSL --max-time 10 \
        "https://clonezilla.org/downloads/download.php?branch=stable" 2>/dev/null \
        | grep -oP 'clonezilla-live-\K[0-9.]+-[0-9]+(?=-amd64)' | head -1)
    ver="${ver:-3.2.0-5}"
    echo "https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/clonezilla-live-${ver}-amd64.iso/download"
    echo "https://downloads.sourceforge.net/project/clonezilla/clonezilla_live_stable/clonezilla-live-${ver}-amd64.iso"
}

resolve_gparted_urls() {
    local ver; ver=$(curl -fsSL --max-time 10 \
        "https://sourceforge.net/projects/gparted/rss" 2>/dev/null \
        | grep -oP 'gparted-live-\K[0-9.]+-[0-9]+(?=-amd64)' | head -1)
    ver="${ver:-1.7.0-1}"
    echo "https://sourceforge.net/projects/gparted/files/gparted-live-stable/gparted-live-${ver}-amd64.iso/download"
}

resolve_systemrescue_urls() {
    local ver; ver=$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/systemrescue/systemrescue-sources/releases/latest" 2>/dev/null \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1)
    ver="${ver:-12.00}"
    echo "https://fastly.cdn.systemmechanics.net/systemrescue/systemrescue-${ver}-amd64.iso"
    echo "https://osdn.net/projects/systemrescue/downloads/$(echo "$ver" | tr . _)/systemrescue-${ver}-amd64.iso/"
}

resolve_memtest_urls() {
    echo "https://www.memtest.org/download/v7.20/mt86plus_7.20_64.iso.zip"
    echo "https://memtest.org/download/v7.20/mt86plus_7.20_64.iso.zip"
}

resolve_tails_urls() {
    local ver; ver=$(curl -fsSL --max-time 10 \
        "https://tails.net/install/v2/Tails/amd64/stable/latest.json" 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+' | head -1)
    ver="${ver:-6.14}"
    echo "https://tails.net/torrents/files/tails-amd64-${ver}.img"
    echo "https://dl.amnesia.boum.org/tails/stable/tails-amd64-${ver}/tails-amd64-${ver}.img"
}

resolve_parrot_urls() {
    local ver; ver=$(curl -fsSL --max-time 10 \
        "https://deb.parrot.sh/parrot/iso/latest/Parrot-security-latest-amd64.iso.sha256" 2>/dev/null \
        | grep -oP 'Parrot-security-\K[0-9.]+(?=_amd64)' | head -1)
    ver="${ver:-6.3}"
    echo "https://deb.parrot.sh/parrot/iso/latest/Parrot-security-${ver}_amd64.iso"
    echo "https://mirrors.dotsrc.org/parrot-iso/Parrot-security-${ver}_amd64.iso"
}

resolve_linuxmint_urls() {   # $1=flavor
    local flavor="$1"
    local ver; ver=$(curl -fsSL --max-time 10 \
        "https://linuxmint.com/download.php" 2>/dev/null \
        | grep -oP 'linuxmint-\K[0-9.]+(?=-'"${flavor}"')' | sort -V | tail -1)
    ver="${ver:-22.1}"
    echo "https://mirrors.xtom.de/linuxmint/linuxmint-${ver}-${flavor}-64bit.iso"
    echo "https://ftpmirror1.infania.net/mint/stable/${ver}/linuxmint-${ver}-${flavor}-64bit.iso"
}

# ── ISO Catalog ───────────────────────────────────────────────────────────────
# Format: NAME|ALIAS|FOLDER|SIZE_MB|URL1[|URL2|URL3]
# SEL array (0/1) is built separately after catalog load

declare -a ISO_CATALOG=()

build_catalog() {
    local deb13g deb13k deb13x deb12g deb12s deb11g
    local ub24d ub24s ub22d ub22s ku24 xu24 lu24 mint_c mint_m mint_x
    local rocky9 alma9 fedora arch kali_live kali_purple parrot tails
    local proxmox truenas clonezilla gparted sysrescue memtest

    info "Building ISO catalog..."

    deb13g=$(resolve_debian_urls gnome 13); deb13k=$(resolve_debian_urls kde 13)
    deb13x=$(resolve_debian_urls xfce 13); deb12g=$(resolve_debian_urls gnome 12)
    deb12s=$(resolve_debian_urls standard 12); deb11g=$(resolve_debian_urls gnome 11)
    ub24d=$(resolve_ubuntu_urls desktop 24.04); ub24s=$(resolve_ubuntu_urls live-server 24.04)
    ub22d=$(resolve_ubuntu_urls desktop 22.04); ub22s=$(resolve_ubuntu_urls live-server 22.04)
    ku24=$(resolve_ubuntu_flavor_urls kubuntu 24.04)
    xu24=$(resolve_ubuntu_flavor_urls xubuntu 24.04)
    lu24=$(resolve_ubuntu_flavor_urls lubuntu 24.04)
    mint_c=$(resolve_linuxmint_urls cinnamon); mint_m=$(resolve_linuxmint_urls mate)
    mint_x=$(resolve_linuxmint_urls xfce)
    rocky9=$(resolve_rocky_urls 9); alma9="https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-minimal.iso"
    fedora=$(resolve_fedora_urls); arch=$(resolve_arch_urls)
    kali_live=$(resolve_kali_urls live-amd64); kali_purple=$(resolve_kali_urls installer-purple-amd64)
    parrot=$(resolve_parrot_urls); tails=$(resolve_tails_urls)
    proxmox=$(resolve_proxmox_urls); truenas=$(resolve_truenas_urls)
    clonezilla=$(resolve_clonezilla_urls); gparted=$(resolve_gparted_urls)
    sysrescue=$(resolve_systemrescue_urls); memtest=$(resolve_memtest_urls)

    ISO_CATALOG=(
        # ── Debian ──────────────────────────────────────────────────────────
        "debian-13-live-amd64-gnome.iso|Debian 13 Trixie - GNOME|Linux/Debian|4500|${deb13g}"
        "debian-13-live-amd64-kde.iso|Debian 13 Trixie - KDE Plasma|Linux/Debian|4500|${deb13k}"
        "debian-13-live-amd64-xfce.iso|Debian 13 Trixie - Xfce|Linux/Debian|4000|${deb13x}"
        "debian-13-live-amd64-cinnamon.iso|Debian 13 Trixie - Cinnamon|Linux/Debian|4000|$(resolve_debian_urls cinnamon 13)"
        "debian-13-live-amd64-mate.iso|Debian 13 Trixie - MATE|Linux/Debian|4000|$(resolve_debian_urls mate 13)"
        "debian-13-live-amd64-lxqt.iso|Debian 13 Trixie - LXQt|Linux/Debian|3500|$(resolve_debian_urls lxqt 13)"
        "debian-13-live-amd64-standard.iso|Debian 13 Trixie - Standard (no DE)|Linux/Debian|1500|$(resolve_debian_urls standard 13)"
        "debian-12-live-amd64-gnome.iso|Debian 12 Bookworm - GNOME|Linux/Debian|4500|${deb12g}"
        "debian-12-live-amd64-kde.iso|Debian 12 Bookworm - KDE Plasma|Linux/Debian|4500|$(resolve_debian_urls kde 12)"
        "debian-12-live-amd64-xfce.iso|Debian 12 Bookworm - Xfce|Linux/Debian|4000|$(resolve_debian_urls xfce 12)"
        "debian-12-live-amd64-cinnamon.iso|Debian 12 Bookworm - Cinnamon|Linux/Debian|4000|$(resolve_debian_urls cinnamon 12)"
        "debian-12-live-amd64-standard.iso|Debian 12 Bookworm - Standard|Linux/Debian|1500|${deb12s}"
        "debian-11-live-amd64-gnome.iso|Debian 11 Bullseye - GNOME|Linux/Debian|4000|${deb11g}"
        "debian-11-live-amd64-xfce.iso|Debian 11 Bullseye - Xfce|Linux/Debian|3500|$(resolve_debian_urls xfce 11)"
        # ── Ubuntu ──────────────────────────────────────────────────────────
        "ubuntu-24.04-desktop-amd64.iso|Ubuntu 24.04 LTS - Desktop (GNOME)|Linux/Ubuntu|5000|${ub24d}"
        "ubuntu-24.04-live-server-amd64.iso|Ubuntu 24.04 LTS - Server|Linux/Ubuntu|2000|${ub24s}"
        "ubuntu-22.04-desktop-amd64.iso|Ubuntu 22.04 LTS - Desktop (GNOME)|Linux/Ubuntu|4500|${ub22d}"
        "ubuntu-22.04-live-server-amd64.iso|Ubuntu 22.04 LTS - Server|Linux/Ubuntu|1500|${ub22s}"
        "ubuntu-20.04-desktop-amd64.iso|Ubuntu 20.04 LTS - Desktop (GNOME)|Linux/Ubuntu|3000|$(resolve_ubuntu_urls desktop 20.04)"
        "kubuntu-24.04-desktop-amd64.iso|Kubuntu 24.04 LTS - KDE Plasma|Linux/Ubuntu|4500|${ku24}"
        "kubuntu-22.04-desktop-amd64.iso|Kubuntu 22.04 LTS - KDE Plasma|Linux/Ubuntu|4000|$(resolve_ubuntu_flavor_urls kubuntu 22.04)"
        "xubuntu-24.04-desktop-amd64.iso|Xubuntu 24.04 LTS - Xfce|Linux/Ubuntu|3500|${xu24}"
        "xubuntu-22.04-desktop-amd64.iso|Xubuntu 22.04 LTS - Xfce|Linux/Ubuntu|3000|$(resolve_ubuntu_flavor_urls xubuntu 22.04)"
        "lubuntu-24.04-desktop-amd64.iso|Lubuntu 24.04 LTS - LXQt|Linux/Ubuntu|3000|${lu24}"
        "linuxmint-cinnamon-64bit.iso|Linux Mint (latest) - Cinnamon|Linux/Ubuntu|3000|${mint_c}"
        "linuxmint-mate-64bit.iso|Linux Mint (latest) - MATE|Linux/Ubuntu|2800|${mint_m}"
        "linuxmint-xfce-64bit.iso|Linux Mint (latest) - Xfce|Linux/Ubuntu|2500|${mint_x}"
        "pop-os_22.04_amd64_intel.iso|Pop!_OS 22.04 - Intel/AMD|Linux/Ubuntu|2500|https://iso.pop-os.org/22.04/amd64/intel/22/pop-os_22.04_amd64_intel_22.iso"
        # ── RHEL ────────────────────────────────────────────────────────────
        "Rocky-9-latest-x86_64-minimal.iso|Rocky Linux 9 - Minimal|Linux/RHEL|1200|${rocky9}"
        "Rocky-8-latest-x86_64-minimal.iso|Rocky Linux 8 - Minimal|Linux/RHEL|1200|$(resolve_rocky_urls 8)"
        "AlmaLinux-9-latest-x86_64-minimal.iso|AlmaLinux 9 - Minimal|Linux/RHEL|1200|${alma9}"
        "AlmaLinux-8-latest-x86_64-minimal.iso|AlmaLinux 8 - Minimal|Linux/RHEL|1200|https://repo.almalinux.org/almalinux/8/isos/x86_64/AlmaLinux-8-latest-x86_64-minimal.iso"
        "Fedora-Workstation-Live-x86_64.iso|Fedora Workstation (latest)|Linux/RHEL|2500|${fedora}"
        "CentOS-Stream-9-boot-x86_64.iso|CentOS Stream 9 - Boot|Linux/RHEL|800|https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-boot.iso"
        # ── Arch ────────────────────────────────────────────────────────────
        "archlinux-x86_64.iso|Arch Linux (latest)|Linux/Arch|1000|${arch}"
        "EndeavourOS-latest.iso|EndeavourOS (latest)|Linux/Arch|3000|https://mirror.alpix.eu/endeavouros/iso/latest-release/EndeavourOS_Nova-11_2025.01.12.iso"
        "manjaro-kde-latest.iso|Manjaro - KDE Plasma|Linux/Arch|4000|https://download.manjaro.org/kde/latest/manjaro-kde-latest-x86_64.iso"
        "manjaro-gnome-latest.iso|Manjaro - GNOME|Linux/Arch|4000|https://download.manjaro.org/gnome/latest/manjaro-gnome-latest-x86_64.iso"
        # ── Security ────────────────────────────────────────────────────────
        "kali-linux-live-amd64.iso|Kali Linux Live (latest)|Security|4000|${kali_live}"
        "kali-linux-installer-purple-amd64.iso|Kali Purple SOC (latest)|Security|4500|${kali_purple}"
        "Parrot-security-amd64.iso|Parrot Security OS (latest)|Security|3500|${parrot}"
        "tails-amd64.img|Tails (latest) - privacy/anon|Security|1500|${tails}"
        # ── Sysadmin ────────────────────────────────────────────────────────
        "proxmox-ve-latest.iso|Proxmox VE (latest)|Sysadmin|1200|${proxmox}"
        "TrueNAS-SCALE-latest.iso|TrueNAS SCALE (latest)|Sysadmin|1500|${truenas}"
        "clonezilla-live-amd64.iso|Clonezilla Live (latest)|Sysadmin|500|${clonezilla}"
        "gparted-live-amd64.iso|GParted Live (latest)|Sysadmin|700|${gparted}"
        # ── Rescue ──────────────────────────────────────────────────────────
        "systemrescue-amd64.iso|SystemRescue (latest)|Rescue|1000|${sysrescue}"
        "HBCD_PE_x64.iso|Hiren's BootCD PE|Rescue|2000|https://www.hirensbootcd.org/files/HBCD_PE_x64.iso"
        "memtest86plus.zip|MemTest86+ (latest)|Rescue|15|${memtest}"
        # ── Windows (manual — no Fido on Linux) ─────────────────────────────
        "Win11_x64.iso|Windows 11 [manual download]|Windows|6000|MANUAL:https://www.microsoft.com/software-download/windows11"
        "Win10_x64.iso|Windows 10 [manual download]|Windows|5000|MANUAL:https://www.microsoft.com/software-download/windows10"
    )
}

# ── Preset packs ─────────────────────────────────────────────────────────────
declare -A PACK_NAMES PACK_USB PACK_DESC PACK_ISOS
declare -a PACK_ORDER=()

define_packs() {
    PACK_ORDER=(RESCUE "FIELD OPS" SYSADMIN DEVOPS ULTIMATE CUSTOM)
    PACK_NAMES[RESCUE]="RESCUE"         PACK_USB[RESCUE]=" 8-12 GB"
    PACK_DESC[RESCUE]="Rescue + repair essentials"
    PACK_ISOS[RESCUE]="Hiren's BootCD PE|GParted Live (latest)|SystemRescue (latest)|MemTest86+ (latest)|Clonezilla Live (latest)"

    PACK_NAMES["FIELD OPS"]="FIELD OPS"  PACK_USB["FIELD OPS"]="   16 GB"
    PACK_DESC["FIELD OPS"]="+ Debian minimal + Ubuntu Server + Kali"
    PACK_ISOS["FIELD OPS"]="Hiren's BootCD PE|GParted Live (latest)|SystemRescue (latest)|MemTest86+ (latest)|Clonezilla Live (latest)|Debian 12 Bookworm - Standard|Ubuntu 24.04 LTS - Server|Kali Linux Live (latest)"

    PACK_NAMES[SYSADMIN]="SYSADMIN"     PACK_USB[SYSADMIN]="   32 GB"
    PACK_DESC[SYSADMIN]="+ Desktop + Rocky + Proxmox + TrueNAS"
    PACK_ISOS[SYSADMIN]="Hiren's BootCD PE|GParted Live (latest)|SystemRescue (latest)|MemTest86+ (latest)|Clonezilla Live (latest)|Debian 13 Trixie - GNOME|Ubuntu 24.04 LTS - Desktop (GNOME)|Ubuntu 24.04 LTS - Server|Rocky Linux 9 - Minimal|Proxmox VE (latest)|TrueNAS SCALE (latest)|Kali Linux Live (latest)"

    PACK_NAMES[DEVOPS]="DEVOPS"         PACK_USB[DEVOPS]="   64 GB"
    PACK_DESC[DEVOPS]="+ Fedora + Arch + Parrot + Tails + Kali Purple"
    PACK_ISOS[DEVOPS]="Hiren's BootCD PE|GParted Live (latest)|SystemRescue (latest)|MemTest86+ (latest)|Clonezilla Live (latest)|Debian 13 Trixie - GNOME|Ubuntu 24.04 LTS - Desktop (GNOME)|Ubuntu 24.04 LTS - Server|Rocky Linux 9 - Minimal|Fedora Workstation (latest)|Arch Linux (latest)|Proxmox VE (latest)|TrueNAS SCALE (latest)|Kali Linux Live (latest)|Kali Purple SOC (latest)|Parrot Security OS (latest)|Tails (latest) - privacy/anon"

    PACK_NAMES[ULTIMATE]="ULTIMATE"     PACK_USB[ULTIMATE]="  128 GB"
    PACK_DESC[ULTIMATE]="All major distros + security + tools"
    PACK_ISOS[ULTIMATE]="Hiren's BootCD PE|GParted Live (latest)|SystemRescue (latest)|MemTest86+ (latest)|Clonezilla Live (latest)|Debian 13 Trixie - GNOME|Debian 12 Bookworm - GNOME|Ubuntu 24.04 LTS - Desktop (GNOME)|Ubuntu 24.04 LTS - Server|Ubuntu 22.04 LTS - Desktop (GNOME)|Ubuntu 22.04 LTS - Server|Rocky Linux 9 - Minimal|Fedora Workstation (latest)|Arch Linux (latest)|Proxmox VE (latest)|TrueNAS SCALE (latest)|Kali Linux Live (latest)|Kali Purple SOC (latest)|Parrot Security OS (latest)|Tails (latest) - privacy/anon"

    PACK_NAMES[CUSTOM]="CUSTOM"         PACK_USB[CUSTOM]="  any GB"
    PACK_DESC[CUSTOM]="Manual selection"  PACK_ISOS[CUSTOM]=""
}

# ── Selection state ───────────────────────────────────────────────────────────
declare -a SEL=()   # 0/1 per ISO_CATALOG index

init_sel() {
    local recommended="Debian 13 Trixie - GNOME|Ubuntu 24.04 LTS - Desktop (GNOME)|Ubuntu 24.04 LTS - Server|Rocky Linux 9 - Minimal|Fedora Workstation (latest)|Arch Linux (latest)|Kali Linux Live (latest)|Kali Purple SOC (latest)|Parrot Security OS (latest)|Tails (latest) - privacy/anon|Proxmox VE (latest)|TrueNAS SCALE (latest)|Clonezilla Live (latest)|GParted Live (latest)|SystemRescue (latest)|Hiren's BootCD PE|MemTest86+ (latest)"
    local i alias
    SEL=()
    for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
        alias=$(cut -d'|' -f2 <<< "${ISO_CATALOG[$i]}")
        if grep -qF "$alias" <<< "$recommended"; then
            SEL+=("1")
        else
            SEL+=("0")
        fi
    done
}

apply_pack() {       # $1=pack_name
    local pname="$1" isos alias i found
    isos="${PACK_ISOS[$pname]:-}"
    for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do SEL[$i]=0; done
    [[ -z "$isos" ]] && return
    for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
        alias=$(cut -d'|' -f2 <<< "${ISO_CATALOG[$i]}")
        if grep -qF "$alias" <<< "$isos"; then
            SEL[$i]=1
        fi
    done
}

# ── TUI Menu ──────────────────────────────────────────────────────────────────

read_key() {
    local key rest
    IFS= read -rsn1 key 2>/dev/null
    if [[ "$key" == $'\033' ]]; then
        IFS= read -rsn2 -t 0.05 rest 2>/dev/null || true
        key="${key}${rest}"
    fi
    case "$key" in
        $'\033[A')   echo UP ;;    $'\033[B')  echo DOWN ;;
        $'\033[C')   echo RIGHT ;; $'\033[D')  echo LEFT ;;
        $'\033[21~') echo F10 ;;   $'\033[21') echo F10 ;;
        $'\033OQ')   echo F2 ;;
        ' ')         echo SPACE ;;
        '')          echo ENTER ;;
        $'\033')     echo ESC ;;
        $'\177'|$'\010') echo BACKSPACE ;;
        [aA])        echo A ;;     [nN]) echo N ;;
        [pP])        echo P ;;     [/])  echo SLASH ;;
        [+])         echo PLUS ;;
        *)           echo "CHAR:$key" ;;
    esac
}

# Build flat row list into parallel arrays
declare -a ROW_T=()      # S=section  I=item
declare -a ROW_IDX=()    # for I: ISO_CATALOG index; for S: section name
declare -a ROW_FOLDER=() # section folder name
declare -a SEC_EXPANDED=()  # per-unique-folder index
declare -a SEC_NAMES=()     # ordered unique folder names

build_rows() {
    local filter_text="${1:-}" i folder alias
    ROW_T=(); ROW_IDX=(); ROW_FOLDER=()

    if [[ -n "$filter_text" ]]; then
        for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
            alias=$(cut -d'|' -f2 <<< "${ISO_CATALOG[$i]}")
            folder=$(cut -d'|' -f3 <<< "${ISO_CATALOG[$i]}")
            if grep -qi "$filter_text" <<< "${alias}${folder}"; then
                ROW_T+=(I); ROW_IDX+=($i); ROW_FOLDER+=("$folder")
            fi
        done
    else
        local sidx
        for (( sidx=0; sidx<${#SEC_NAMES[@]}; sidx++ )); do
            folder="${SEC_NAMES[$sidx]}"
            ROW_T+=(S); ROW_IDX+=($sidx); ROW_FOLDER+=("$folder")
            if [[ "${SEC_EXPANDED[$sidx]}" == "1" ]]; then
                for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
                    if [[ "$(cut -d'|' -f3 <<< "${ISO_CATALOG[$i]}")" == "$folder" ]]; then
                        ROW_T+=(I); ROW_IDX+=($i); ROW_FOLDER+=("$folder")
                    fi
                done
            fi
        done
    fi
}

init_sections() {
    local i folder
    SEC_NAMES=(); SEC_EXPANDED=()
    declare -A seen=()
    for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
        folder=$(cut -d'|' -f3 <<< "${ISO_CATALOG[$i]}")
        if [[ -z "${seen[$folder]+x}" ]]; then
            seen[$folder]=1
            SEC_NAMES+=("$folder")
            SEC_EXPANDED+=(0)
        fi
    done
}

get_sec_idx() {   # $1=folder  → sets $SEC_IDX
    local i
    for (( i=0; i<${#SEC_NAMES[@]}; i++ )); do
        [[ "${SEC_NAMES[$i]}" == "$1" ]] && { SEC_IDX=$i; return; }
    done
    SEC_IDX=-1
}

render_header() {
    local W="$1" selCount="$2" totalGB="$3" selPct="$4"
    local title="  MULTIBOOT  /  USB  COMMANDER  "
    local starsA=" *  .    *  .  *    .  *    .  *  .    *  "
    local starsB="  .    *  .  *    .  *    .  *  "
    wl "${VD}${starsA}${RST}${CY}${BLD}${title}${RST}${VD}${starsB}${RST}" "$W"
    wl "${BL}$(printf '=%.0s' $(seq 1 $W))${RST}" "$W"
    local bar; bar=$(mkbar "$selPct" 100 32)
    local statsAns="  ${YL}${BLD}PAYLOAD${RST}  ${CY}${BLD}${selCount}${RST} ${DM}units${RST}  ${OR}~${totalGB} GB${RST}   ${bar}   ${WH}${selPct}%${RST}  ${GR}READY${RST}"
    wl "$statsAns" "$W"
    wl "${VD}$(printf -- '-%.0s' $(seq 1 $W))${RST}" "$W"
}

render_footer() {
    local W="$1" filter_mode="$2" filter_text="$3"
    wl "${VD}$(printf -- '-%.0s' $(seq 1 $W))${RST}" "$W"
    if [[ "$filter_mode" == "1" ]]; then
        wl "  ${CY}[?] SCAN: type to filter   [BKSP] delete   [ESC] abort   [+] add beacon${RST}" "$W"
    else
        wl "  ${BL}[/] scan   [+] beacon   [P] packs   [SPC] lock   [ENTER] sector   [A/N] all/none   [F10] LAUNCH${RST}" "$W"
    fi
    wl "${BL}$(printf '=%.0s' $(seq 1 $W))${RST}" "$W"
}

show_iso_menu() {
    local CURSOR=0 VIEW_TOP=0
    local FILTER_MODE=0 FILTER_TEXT=""
    local PACK_MODE=0 PACK_CURSOR=0

    init_sections
    build_rows ""

    printf '\033[?25l'   # hide cursor
    printf '\033[2J'     # clear screen

    trap 'printf "\033[?25h"; printf "\033[0m"; stty sane 2>/dev/null; exit' INT TERM EXIT

    while true; do
        local W; W=$(( $(tput cols 2>/dev/null || echo 90) ))
        [[ $W -gt 90 ]] && W=90
        local WIN_H; WIN_H=$(tput lines 2>/dev/null || echo 30)
        local VIEW_H=$(( WIN_H - 8 ))
        [[ $VIEW_H -lt 4 ]] && VIEW_H=4

        # Totals
        local totalMB=0 selCount=0 i alias sizemb
        for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
            if [[ "${SEL[$i]}" == "1" ]]; then
                sizemb=$(cut -d'|' -f4 <<< "${ISO_CATALOG[$i]}")
                totalMB=$(( totalMB + sizemb ))
                selCount=$(( selCount + 1 ))
            fi
        done
        local totalGB selPct
        totalGB=$(awk "BEGIN{printf \"%.1f\", $totalMB/1024}")
        [[ "${#SEL[@]}" -gt 0 ]] && selPct=$(( selCount * 100 / ${#SEL[@]} )) || selPct=0

        # Clamp cursor
        local nrows=${#ROW_T[@]}
        [[ $CURSOR -ge $nrows && $nrows -gt 0 ]] && CURSOR=$(( nrows - 1 ))
        [[ $CURSOR -lt 0 ]] && CURSOR=0
        [[ $CURSOR -lt $VIEW_TOP ]] && VIEW_TOP=$CURSOR
        [[ $CURSOR -ge $(( VIEW_TOP + VIEW_H )) ]] && VIEW_TOP=$(( CURSOR - VIEW_H + 1 ))
        [[ $VIEW_TOP -lt 0 ]] && VIEW_TOP=0

        # ── Build frame ──────────────────────────────────────────────────────
        local FRAME=""
        FRAME+="${E}[H"   # cursor to (0,0)

        # ── Pack selection overlay ───────────────────────────────────────────
        if [[ $PACK_MODE -eq 1 ]]; then
            FRAME+="$(wl "${VD} *  .    *  .  *    .  *    MULTIBOOT / USB COMMANDER    *  .  *${RST}" "$W")"
            FRAME+="$(wl "${BL}$(printf '=%.0s' $(seq 1 $W))${RST}" "$W")"
            FRAME+="$(wl "  ${CY}${BLD}PRESET PACKS${RST}  ${DM}ENTER apply   ESC cancel${RST}" "$W")"
            FRAME+="$(wl "${VD}$(printf -- '-%.0s' $(seq 1 $W))${RST}" "$W")"
            FRAME+="$(wl "" "$W")"
            local pi=0 pn
            for pn in "${PACK_ORDER[@]}"; do
                local piso_count=0 pmb=0
                if [[ -n "${PACK_ISOS[$pn]}" ]]; then
                    IFS='|' read -ra pisos <<< "${PACK_ISOS[$pn]}"
                    piso_count=${#pisos[@]}
                    for palias in "${pisos[@]}"; do
                        for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
                            if grep -qF "$palias" <<< "$(cut -d'|' -f2 <<< "${ISO_CATALOG[$i]}")"; then
                                local smb; smb=$(cut -d'|' -f4 <<< "${ISO_CATALOG[$i]}")
                                pmb=$(( pmb + smb ))
                            fi
                        done
                    done
                fi
                local pgb="---"
                [[ $pmb -gt 0 ]] && pgb="~$(awk "BEGIN{printf \"%.0f\", $pmb/1024}") GB"
                local nm pgb_pad usb_str line
                nm="$(printf '%-12s' "${PACK_NAMES[$pn]}")"
                usb_str="${PACK_USB[$pn]}"
                pgb_pad="$(printf '%-10s' "$pgb")"
                local cnt_str=""; [[ $piso_count -gt 0 ]] && cnt_str="(${piso_count} ISOs)"
                line=" ${nm}  ${usb_str}   ${pgb_pad}  ${PACK_DESC[$pn]}  ${DM}${cnt_str}"
                if [[ $pi -eq $PACK_CURSOR ]]; then
                    FRAME+="$(wl "  ${BG_CUR}${CY}${BLD}>> ${line}${RST}" "$W")"
                else
                    FRAME+="$(wl "     ${GY}${line}${RST}" "$W")"
                fi
                pi=$(( pi + 1 ))
            done
            FRAME+="$(wl "" "$W")"
            local drawn=$(( pi + 6 ))
            while [[ $drawn -lt $(( WIN_H - 3 )) ]]; do
                FRAME+="$(wl "" "$W")"; drawn=$(( drawn + 1 ))
            done
            FRAME+="$(wl "${VD}$(printf -- '-%.0s' $(seq 1 $W))${RST}" "$W")"
            FRAME+="$(wl "  ${BL}[up/down] navigate   [ENTER] apply pack   [ESC] cancel${RST}" "$W")"
            FRAME+="$(wl "${BL}$(printf '=%.0s' $(seq 1 $W))${RST}" "$W")"
            printf '%s' "$FRAME"

            local k; k=$(read_key)
            case "$k" in
                UP)    [[ $PACK_CURSOR -gt 0 ]] && PACK_CURSOR=$(( PACK_CURSOR - 1 )) ;;
                DOWN)  [[ $PACK_CURSOR -lt $(( ${#PACK_ORDER[@]} - 1 )) ]] && PACK_CURSOR=$(( PACK_CURSOR + 1 )) ;;
                ESC)   PACK_MODE=0 ;;
                ENTER)
                    local chosen="${PACK_ORDER[$PACK_CURSOR]}"
                    apply_pack "$chosen"
                    PACK_MODE=0
                    build_rows ""
                    ;;
            esac
            continue
        fi

        # ── Normal render ────────────────────────────────────────────────────
        FRAME+="$(render_header "$W" "$selCount" "$totalGB" "$selPct")"

        # Context help
        local cur_t="" cur_folder=""
        if [[ $nrows -gt 0 && $CURSOR -lt $nrows ]]; then
            cur_t="${ROW_T[$CURSOR]}"; cur_folder="${ROW_FOLDER[$CURSOR]}"
        fi
        if [[ $FILTER_MODE -eq 1 ]]; then
            FRAME+="$(wl "  ${CY}[ SCAN: ${FILTER_TEXT}_ ]${RST}  ${DM}Type to filter   BKSP delete   ESC cancel   + beacon${RST}" "$W")"
        elif [[ "$cur_t" == "S" ]]; then
            FRAME+="$(wl "  ${DM}ENTER open sector   SPC lock all   / scan   + beacon   A all   N none   F10 LAUNCH${RST}" "$W")"
        else
            FRAME+="$(wl "  ${DM}SPC lock/unlock   ${ARR_L} back   / scan   + beacon   A all   N none   F10 LAUNCH${RST}" "$W")"
        fi

        # Viewport
        local view_end=$(( VIEW_TOP + VIEW_H - 1 ))
        [[ $view_end -ge $nrows ]] && view_end=$(( nrows - 1 ))
        local drawn=0 r

        if [[ $nrows -eq 0 ]]; then
            if [[ $FILTER_MODE -eq 1 ]]; then
                FRAME+="$(wl "  ${YL}-- NO SIGNAL FOR '${FILTER_TEXT}' --   ${DM}Use + to add a custom beacon URL${RST}" "$W")"
            else
                FRAME+="$(wl "" "$W")"
            fi
            drawn=1
        fi

        for (( r=VIEW_TOP; r<=view_end; r++ )); do
            local rt="${ROW_T[$r]}" ridx="${ROW_IDX[$r]}" rfolder="${ROW_FOLDER[$r]}"
            if [[ "$rt" == "S" ]]; then
                local sidx=$ridx
                local exp="${SEC_EXPANDED[$sidx]}"
                local exp_char; [[ "$exp" == "1" ]] && exp_char="$ARR_D" || exp_char="$ARR_R"
                # Count sel/total for this section
                local sc=0 tc=0 smb=0
                for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
                    if [[ "$(cut -d'|' -f3 <<< "${ISO_CATALOG[$i]}")" == "$rfolder" ]]; then
                        tc=$(( tc + 1 ))
                        if [[ "${SEL[$i]}" == "1" ]]; then
                            sc=$(( sc + 1 ))
                            smb=$(( smb + $(cut -d'|' -f4 <<< "${ISO_CATALOG[$i]}") ))
                        fi
                    fi
                done
                local sgb; sgb=$(awk "BEGIN{printf \"%.1f\", $smb/1024}")
                local lock_icon; if [[ $sc -eq $tc ]]; then lock_icon="${GR}[${CHK}]${RST}"; elif [[ $sc -eq 0 ]]; then lock_icon="${VD}[ ]${RST}"; else lock_icon="${YL}[-]${RST}"; fi
                local bar; bar=$(mkbar $sc $tc 10)
                local fpad; fpad=$(printf '%-22s' "$rfolder")
                local stxt=" ${sc}/${tc}  ~${sgb} GB"
                local line="   ${lock_icon} ${BL}${exp_char}${RST} ${YL}${fpad}${RST}${DM}${stxt}  ${bar}${RST}"
                if [[ $r -eq $CURSOR ]]; then
                    line="  ${BG_SEC}${WH}${BLD} ${exp_char} ${lock_icon}${BG_SEC}${WH} ${fpad}${DM}${stxt}  ${bar}${RST}"
                fi
                FRAME+="$(wl "$line" "$W")"
            else
                local iidx=$ridx
                local iso_entry="${ISO_CATALOG[$iidx]}"
                local iso_alias; iso_alias=$(cut -d'|' -f2 <<< "$iso_entry")
                local iso_size; iso_size=$(cut -d'|' -f4 <<< "$iso_entry")
                local url1; url1=$(cut -d'|' -f5 <<< "$iso_entry")
                local is_manual=0; [[ "$url1" == MANUAL:* ]] && is_manual=1
                local sym col
                if [[ $is_manual -eq 1 ]]; then
                    sym="${VD}[ ]${RST}"; col="$VD"
                elif [[ "${SEL[$iidx]}" == "1" ]]; then
                    sym="${GR}[${CHK}]${RST}"; col="$WH"
                else
                    sym="${DM}[ ]${RST}"; col="$DM"
                fi
                local sz=""
                [[ "$iso_size" -gt 0 ]] && sz="  ~$(awk "BEGIN{printf \"%.1f\", $iso_size/1024}") GB"
                local ctx=""
                [[ $FILTER_MODE -eq 1 ]] && ctx=" ${VD}[$(cut -d'|' -f3 <<< "$iso_entry")]${RST}"
                local aw=$(( W - 14 - ${#sz} ))
                local at; at=$(printf '%-*s' "$aw" "$iso_alias")
                [[ ${#iso_alias} -gt $aw ]] && at="${iso_alias:0:$(( aw - 1 ))}>"
                local visL="      [.]  ${at}${sz}"
                local ansL="      ${sym}  ${col}${at}${DM}${sz}${ctx}${RST}"
                if [[ $r -eq $CURSOR ]]; then
                    FRAME+="$(wl "${BG_CUR}${CY}${BLD}${visL}${RST}" "$W")"
                else
                    FRAME+="$(wl "$ansL" "$W")"
                fi
            fi
            drawn=$(( drawn + 1 ))
        done
        while [[ $drawn -lt $VIEW_H ]]; do
            FRAME+="$(wl "" "$W")"; drawn=$(( drawn + 1 ))
        done

        FRAME+="$(render_footer "$W" "$FILTER_MODE" "$FILTER_TEXT")"

        printf '%s' "$FRAME"

        # ── Key input ────────────────────────────────────────────────────────
        stty -echo -icanon min 1 time 0 2>/dev/null
        local k; k=$(read_key)
        stty echo icanon 2>/dev/null

        # + beacon (custom URL)
        if [[ "$k" == "PLUS" ]]; then
            printf '\033[?25h'
            local brow=$(( WIN_H - 5 ))
            printf '\033[%d;0H' "$brow"
            printf "  ${CY}${BLD}[+] BEACON URL (https://...):${RST}  "
            stty echo icanon 2>/dev/null
            local burl; read -r burl
            if [[ "$burl" =~ ^https?:// ]]; then
                local bname; bname=$(basename "${burl%%\?*}")
                local bext="${bname##*.}"
                local bsize=0
                local bclen; bclen=$(curl -fsSLI --max-time 8 "$burl" 2>/dev/null | grep -i content-length | tail -1 | awk '{print $2}' | tr -d $'\r')
                [[ "$bclen" =~ ^[0-9]+$ ]] && bsize=$(( bclen / 1024 / 1024 ))
                printf "  ${GR}  SIGNAL: .${bext}   MASS: ~%d MB${RST}\n" "$bsize"
                printf "  ${CY}  CALLSIGN [%s]:${RST}  " "$bname"
                local bcallsign; read -r bcallsign
                [[ -z "$bcallsign" ]] && bcallsign="$bname"
                ISO_CATALOG+=("${bname}|${bcallsign}|Custom/Beacons|${bsize}|${burl}")
                SEL+=("1")
                local already=0
                for f in "${SEC_NAMES[@]}"; do [[ "$f" == "Custom/Beacons" ]] && { already=1; break; }; done
                [[ $already -eq 0 ]] && { SEC_NAMES+=("Custom/Beacons"); SEC_EXPANDED+=(1); }
                build_rows ""
            fi
            printf '\033[?25l'
            printf '\033[2J'
            continue
        fi

        # Filter mode
        if [[ $FILTER_MODE -eq 1 ]]; then
            case "$k" in
                ESC)       FILTER_MODE=0; FILTER_TEXT=""; CURSOR=0; VIEW_TOP=0; build_rows "" ;;
                BACKSPACE) [[ ${#FILTER_TEXT} -gt 0 ]] && FILTER_TEXT="${FILTER_TEXT%?}"; CURSOR=0; VIEW_TOP=0; build_rows "$FILTER_TEXT" ;;
                UP)        [[ $CURSOR -gt 0 ]] && CURSOR=$(( CURSOR - 1 )) ;;
                DOWN)      [[ $CURSOR -lt $(( nrows - 1 )) ]] && CURSOR=$(( CURSOR + 1 )) ;;
                SPACE)
                    if [[ $CURSOR -lt $nrows && "${ROW_T[$CURSOR]}" == "I" ]]; then
                        local ii="${ROW_IDX[$CURSOR]}"
                        local u1; u1=$(cut -d'|' -f5 <<< "${ISO_CATALOG[$ii]}")
                        [[ "$u1" != MANUAL:* ]] && { [[ "${SEL[$ii]}" == "1" ]] && SEL[$ii]=0 || SEL[$ii]=1; }
                    fi ;;
                ENTER|F10) break ;;
                CHAR:*)
                    local ch="${k#CHAR:}"
                    [[ -n "$ch" ]] && { FILTER_TEXT+="$ch"; CURSOR=0; VIEW_TOP=0; build_rows "$FILTER_TEXT"; }
                    ;;
            esac
            continue
        fi

        # Normal mode
        case "$k" in
            UP)
                if [[ $CURSOR -gt 0 ]]; then
                    CURSOR=$(( CURSOR - 1 ))
                fi ;;
            DOWN)
                if [[ $CURSOR -lt $(( nrows - 1 )) ]]; then
                    CURSOR=$(( CURSOR + 1 ))
                fi ;;
            RIGHT)
                if [[ $CURSOR -lt $nrows && "${ROW_T[$CURSOR]}" == "S" ]]; then
                    local sidx="${ROW_IDX[$CURSOR]}"
                    if [[ "${SEC_EXPANDED[$sidx]}" != "1" ]]; then
                        SEC_EXPANDED[$sidx]=1; build_rows ""
                    else
                        local nc=$(( CURSOR + 1 ))
                        [[ $nc -lt $nrows && "${ROW_T[$nc]}" == "I" ]] && CURSOR=$nc
                    fi
                fi ;;
            LEFT)
                if [[ $CURSOR -lt $nrows ]]; then
                    if [[ "${ROW_T[$CURSOR]}" == "S" ]]; then
                        local sidx="${ROW_IDX[$CURSOR]}"
                        SEC_EXPANDED[$sidx]=0; build_rows ""
                    elif [[ "${ROW_T[$CURSOR]}" == "I" ]]; then
                        local ifolder="${ROW_FOLDER[$CURSOR]}"
                        for (( r=CURSOR-1; r>=0; r-- )); do
                            if [[ "${ROW_T[$r]}" == "S" && "${ROW_FOLDER[$r]}" == "$ifolder" ]]; then
                                CURSOR=$r; break
                            fi
                        done
                    fi
                fi ;;
            ENTER)
                if [[ $CURSOR -lt $nrows ]]; then
                    if [[ "${ROW_T[$CURSOR]}" == "S" ]]; then
                        local sidx="${ROW_IDX[$CURSOR]}"
                        if [[ "${SEC_EXPANDED[$sidx]}" == "1" ]]; then
                            SEC_EXPANDED[$sidx]=0
                        else
                            SEC_EXPANDED[$sidx]=1
                            CURSOR=$(( CURSOR + 1 ))
                        fi
                        build_rows ""
                    else
                        break  # confirm selection
                    fi
                fi ;;
            SPACE)
                if [[ $CURSOR -lt $nrows ]]; then
                    if [[ "${ROW_T[$CURSOR]}" == "S" ]]; then
                        local sidx="${ROW_IDX[$CURSOR]}"
                        local sfolder="${SEC_NAMES[$sidx]}"
                        local sc=0 tc=0
                        for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
                            [[ "$(cut -d'|' -f3 <<< "${ISO_CATALOG[$i]}")" == "$sfolder" ]] || continue
                            tc=$(( tc + 1 ))
                            [[ "${SEL[$i]}" == "1" ]] && sc=$(( sc + 1 ))
                        done
                        local newval; [[ $sc -eq $tc ]] && newval=0 || newval=1
                        for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
                            if [[ "$(cut -d'|' -f3 <<< "${ISO_CATALOG[$i]}")" == "$sfolder" ]]; then
                                local u1; u1=$(cut -d'|' -f5 <<< "${ISO_CATALOG[$i]}")
                                [[ "$u1" != MANUAL:* ]] && SEL[$i]=$newval
                            fi
                        done
                    elif [[ "${ROW_T[$CURSOR]}" == "I" ]]; then
                        local ii="${ROW_IDX[$CURSOR]}"
                        local u1; u1=$(cut -d'|' -f5 <<< "${ISO_CATALOG[$ii]}")
                        if [[ "$u1" != MANUAL:* ]]; then
                            [[ "${SEL[$ii]}" == "1" ]] && SEL[$ii]=0 || SEL[$ii]=1
                        fi
                    fi
                fi ;;
            SLASH) FILTER_MODE=1; FILTER_TEXT=""; CURSOR=0; VIEW_TOP=0; build_rows "$FILTER_TEXT" ;;
            P)     PACK_MODE=1; PACK_CURSOR=0 ;;
            A)     for (( i=0; i<${#SEL[@]}; i++ )); do
                       local u1; u1=$(cut -d'|' -f5 <<< "${ISO_CATALOG[$i]}")
                       [[ "$u1" != MANUAL:* ]] && SEL[$i]=1
                   done ;;
            N)     for (( i=0; i<${#SEL[@]}; i++ )); do SEL[$i]=0; done ;;
            F10|ESC) break ;;
        esac
    done

    printf '\033[?25h'
    printf '\033[0m'
    stty sane 2>/dev/null || true
    trap - INT TERM EXIT
}

# ── Download ──────────────────────────────────────────────────────────────────

download_file() {   # $1=url  $2=outfile  $3=min_bytes(optional)
    local url="$1" outfile="$2" min="${3:-1048576}"
    local attempt=1
    while [[ $attempt -le 2 ]]; do
        info "Attempt ${attempt}/2"
        if curl -L --retry 1 --retry-delay 3 -C - \
               --progress-bar --max-time 3600 \
               -o "$outfile" "$url" 2>&1; then
            local sz=0
            sz=$(stat -c%s "$outfile" 2>/dev/null || stat -f%z "$outfile" 2>/dev/null || echo 0)
            if [[ $sz -ge $min ]]; then
                ok "Downloaded ($(awk "BEGIN{printf \"%.0f\", $sz/1024/1024}") MB)"
                return 0
            else
                warn "File too small (${sz} bytes), retrying..."
                rm -f "$outfile"
            fi
        fi
        attempt=$(( attempt + 1 ))
    done
    return 1
}

# ── ventoy.json ───────────────────────────────────────────────────────────────

generate_ventoy_json() {   # $1=usb_mount  $2=title  $3=theme_slug
    local usb="$1" title="$2" slug="$3"
    local cfg_dir="${usb}/ventoy"
    mkdir -p "$cfg_dir"
    cat > "${cfg_dir}/ventoy.json" <<JSON
{
    "menu_title": "${title}",
    "menu_timeout": 30,
    "default_image": "",
    "theme": {
        "file": "/ventoy/themes/${slug}/theme.txt",
        "gfxmode": "1920x1080",
        "display_mode": "CLI",
        "serial_param": "",
        "ventoy_static_bg": 0
    },
    "control": [
        { "VTOY_DEFAULT_MENU_MODE": "0" },
        { "VTOY_FIRT_INSTALL_CHECK": "0" }
    ]
}
JSON
    ok "ventoy.json written"
}

# ── Banner ────────────────────────────────────────────────────────────────────

show_banner() {
    printf '\033[2J\033[H'
    cat <<EOF

${CY}${BLD}  ══════════════════════════════════════════════════════════${RST}
${CY}${BLD}    MULTIBOOT  /  USB  COMMANDER   —   Linux Edition        ${RST}
${CY}${BLD}  ══════════════════════════════════════════════════════════${RST}
     ${DM}Ventoy multiboot USB builder — bash native${RST}

     ${DM}Language  : ${WH}${LANGUAGE}${RST}
     ${DM}Title     : ${WH}${TITLE}${RST}
     ${DM}Cache dir : ${WH}${DOWNLOAD_DIR}${RST}
     ${DM}USB mount : ${WH}${USB_MOUNT:-autodetect}${RST}

EOF
}

# ── Admin check ───────────────────────────────────────────────────────────────

check_admin() {
    if [[ $(id -u) -ne 0 ]]; then
        warn "Not running as root. Some operations may require sudo."
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    check_admin

    # Language
    if [[ -z "$LANGUAGE" ]]; then
        printf "  Select language / Selecciona idioma [en/es, ENTER=en]: "
        read -r inp
        [[ "${inp,,}" == "es" ]] && LANGUAGE="es" || LANGUAGE="en"
    fi

    # Title
    if [[ -z "$TITLE" ]]; then
        printf "\n  Name for your multiboot USB (e.g. MYBOOT, LABUSB):\n"
        printf "  Name [ENTER=MYBOOT]: "
        read -r inp
        [[ -z "$inp" ]] && TITLE="MYBOOT" || TITLE="$inp"
    fi

    # Download mode (direct-to-USB vs cache+copy)
    if [[ $USE_DIRECT -eq 0 && $USE_CACHE -eq 0 ]]; then
        printf "\n  Download mode:\n"
        printf "  [D] Direct to USB  (faster, no cache reuse, requires USB ready)\n"
        printf "  [C] Cache + copy   (slower, cache reusable for other USBs)\n"
        printf "  Mode [D/c, ENTER=D]: "
        read -r inp
        case "${inp,,}" in
            c|cache) USE_CACHE=1 ;;
            *)       USE_DIRECT=1 ;;
        esac
    fi
    if [[ $USE_DIRECT -eq 1 ]]; then
        ok "Mode: DIRECT to USB (downloads written straight to USB)"
    else
        ok "Mode: CACHE + COPY (downloads cached, then copied to USB)"
    fi

    # Download dir (still used for Ventoy installer / tooling even in direct mode)
    if [[ -z "$DOWNLOAD_DIR" ]]; then
        local default_dir="$HOME/${TITLE}_cache"
        printf "\n  ISO download/cache directory:\n"
        printf "  Directory [ENTER=%s]: " "$default_dir"
        read -r inp
        [[ -z "$inp" ]] && DOWNLOAD_DIR="$default_dir" || DOWNLOAD_DIR="$inp"
    fi
    mkdir -p "$DOWNLOAD_DIR"

    # Persistence
    if [[ $SKIP_PERSISTENCE -eq 0 ]]; then
        printf "\n  Create Kali Linux persistence partition? [Y/N, ENTER=Y]: "
        read -r inp
        if [[ "${inp,,}" == "n" || "${inp,,}" == "no" ]]; then
            SKIP_PERSISTENCE=1
        else
            printf "  Persistence size in MB [ENTER=%d]: " "$PERSISTENCE_MB"
            read -r inp
            [[ "$inp" =~ ^[0-9]+$ && $inp -gt 0 ]] && PERSISTENCE_MB=$inp
        fi
    fi

    show_banner

    # === Build catalog + menu ===
    step "Loading ISO catalog..."
    build_catalog
    define_packs
    init_sel

    step "ISO Selection Menu"
    printf '\n'
    show_iso_menu

    # Collect selected ISOs
    local selected_isos=()
    local i
    for (( i=0; i<${#ISO_CATALOG[@]}; i++ )); do
        [[ "${SEL[$i]}" == "1" ]] && selected_isos+=("${ISO_CATALOG[$i]}")
    done
    printf "\n  ${GR}${BLD}%d ISOs selected${RST}\n\n" "${#selected_isos[@]}"

    # === 1) Ventoy ===
    if [[ $SKIP_VENTOY -eq 0 ]]; then
        step "1/7  Resolving Ventoy"
        local vt_ver vt_url vt_name
        vt_ver=$(curl -fsSL --max-time 15 \
            "https://api.github.com/repos/ventoy/Ventoy/releases/latest" 2>/dev/null \
            | grep -oP '"tag_name"\s*:\s*"v\K[^"]+' | head -1)
        vt_ver="${vt_ver:-1.1.11}"
        vt_name="ventoy-${vt_ver}-linux.tar.gz"
        vt_url="https://github.com/ventoy/Ventoy/releases/download/v${vt_ver}/${vt_name}"
        ok "Ventoy v${vt_ver}"

        local vt_archive="${DOWNLOAD_DIR}/${vt_name}"
        if [[ ! -f "$vt_archive" ]]; then
            info "URL: $vt_url"
            download_file "$vt_url" "$vt_archive" $((1*1024*1024))
        fi
        tar -xzf "$vt_archive" -C "$DOWNLOAD_DIR" 2>/dev/null && ok "Ventoy extracted"

        step "2/7  Locating Ventoy installer"
        local vt_sh
        vt_sh=$(find "$DOWNLOAD_DIR" -name 'Ventoy2Disk.sh' 2>/dev/null | head -1)
        if [[ -z "$vt_sh" ]]; then
            err "Ventoy2Disk.sh not found. Download manually or use -V to skip."
        else
            ok "Found: $vt_sh"
            if [[ -z "$USB_DEVICE" ]]; then
                printf "\n"
                lsblk -o NAME,SIZE,RM,LABEL,VENDOR,MODEL 2>/dev/null || true
                printf "\n"
                printf "  Block device to install Ventoy on (e.g. /dev/sdb, ENTER to skip): "
                read -r USB_DEVICE
            fi
            if [[ -n "$USB_DEVICE" ]]; then
                info "Running: sudo bash $vt_sh -I $USB_DEVICE"
                sudo bash "$vt_sh" -I "$USB_DEVICE" && ok "Ventoy installed on $USB_DEVICE"
            else
                info "Skipping Ventoy install (no device specified)"
            fi
        fi
    else
        info "Skipping Ventoy install (-V)"
    fi

    # === 3) Detect USB ===
    step "3/7  Detecting Ventoy USB"
    if [[ -n "$USB_MOUNT" ]]; then
        ok "USB: $USB_MOUNT"
    else
        # Try auto-detect by label
        local lsblk_out
        lsblk_out=$(lsblk -J -o NAME,LABEL,MOUNTPOINTS 2>/dev/null || echo '{}')
        USB_MOUNT=$(printf '%s' "$lsblk_out" | grep -oP '"label"\s*:\s*"[Vv][Ee][Nn][Tt][Oo][Yy]"[^}]*?"mountpoints"\s*:\s*\["?\K[^"\]]+' | head -1 || true)
        # Fallback: check /proc/mounts
        if [[ -z "$USB_MOUNT" ]]; then
            USB_MOUNT=$(grep -i ventoy /proc/mounts 2>/dev/null | awk '{print $2}' | head -1 || true)
        fi
        if [[ -n "$USB_MOUNT" ]]; then
            ok "USB: $USB_MOUNT"
        else
            warn "No Ventoy USB found."
            lsblk -o NAME,SIZE,RM,LABEL,MOUNTPOINTS 2>/dev/null || true
            printf "\n  Ventoy USB mount point (e.g. /media/user/Ventoy, ENTER to abort): "
            read -r USB_MOUNT
            [[ -z "$USB_MOUNT" ]] && { err "Aborted."; exit 1; }
        fi
    fi
    USB_MOUNT="${USB_MOUNT%/}"
    [[ ! -d "$USB_MOUNT" ]] && { err "Mount point '$USB_MOUNT' not found or not a directory."; exit 1; }

    # Disk space check
    local usb_free_mb usb_needed_mb=0
    usb_free_mb=$(df -m "$USB_MOUNT" 2>/dev/null | tail -1 | awk '{print $4}')
    for entry in "${selected_isos[@]}"; do
        local sz; sz=$(cut -d'|' -f4 <<< "$entry")
        usb_needed_mb=$(( usb_needed_mb + sz ))
    done
    local usb_free_gb usb_needed_gb
    usb_free_gb=$(awk "BEGIN{printf \"%.1f\", ${usb_free_mb:-0}/1024}")
    usb_needed_gb=$(awk "BEGIN{printf \"%.1f\", ${usb_needed_mb}/1024}")
    info "Available: ${usb_free_gb} GB  |  ISOs: ~${usb_needed_gb} GB"

    # === 4) Download ISOs ===
    step "4/7  Downloading ISOs"
    local total_isos=${#selected_isos[@]} idx=0 ok_count=0 fail_count=0 skip_count=0
    declare -A results=()

    for entry in "${selected_isos[@]}"; do
        idx=$(( idx + 1 ))
        local fname; fname=$(cut -d'|' -f1 <<< "$entry")
        local alias; alias=$(cut -d'|' -f2 <<< "$entry")
        local folder; folder=$(cut -d'|' -f3 <<< "$entry")
        local url1; url1=$(cut -d'|' -f5 <<< "$entry")

        step "[${idx}/${total_isos}]  ${alias}"

        # Manual entries
        if [[ "$url1" == MANUAL:* ]]; then
            local manual_url="${url1#MANUAL:}"
            warn "Manual download required: $manual_url"
            warn "Place ISO in: ${DOWNLOAD_DIR}/${fname}"
            results[$fname]="MANUAL"
            continue
        fi

        local usb_folder="${USB_MOUNT}/${folder//\\/\/}"
        local usb_file="${usb_folder}/${fname}"
        local cache_file="${DOWNLOAD_DIR}/${fname}"
        mkdir -p "$usb_folder"

        # Already on USB?
        if [[ -f "$usb_file" ]]; then
            ok "Already on USB. Skipping."
            results[$fname]="OK"
            ok_count=$(( ok_count + 1 ))
            continue
        fi

        # Pick where the download lands
        local dl_target
        if [[ $USE_DIRECT -eq 1 ]]; then
            dl_target="$usb_file"
            info "Downloading directly to USB..."
        else
            dl_target="$cache_file"
        fi

        # Already cached? (only relevant in cache mode)
        local already_have=0
        if [[ $USE_DIRECT -eq 0 && -f "$cache_file" ]]; then
            local csz; csz=$(stat -c%s "$cache_file" 2>/dev/null || echo 0)
            if [[ $csz -gt $((512*1024)) ]]; then
                ok "Already cached ($(awk "BEGIN{printf \"%.0f\", $csz/1024/1024}") MB). Using cache."
                already_have=1
            fi
        fi

        if [[ $already_have -eq 0 ]]; then
            # Download with URL fallback
            local dl_ok=0
            local urls=(); IFS='|' read -ra url_fields <<< "$entry"
            for (( ui=4; ui<${#url_fields[@]}; ui++ )); do
                local u="${url_fields[$ui]}"
                [[ -z "$u" ]] && continue
                info "URL: $u"
                if download_file "$u" "$dl_target" 512000; then
                    dl_ok=1; break
                fi
            done
            if [[ $dl_ok -eq 0 ]]; then
                err "Download failed: $alias"
                # Clean up partial USB write if direct mode failed
                [[ $USE_DIRECT -eq 1 && -f "$dl_target" ]] && rm -f "$dl_target"
                results[$fname]="FAILED"
                fail_count=$(( fail_count + 1 ))
                continue
            fi
        fi

        # Direct mode: file is already at $usb_file, no copy needed
        if [[ $USE_DIRECT -eq 1 ]]; then
            ok "Done (direct)"
            results[$fname]="OK"
            ok_count=$(( ok_count + 1 ))
            continue
        fi

        # Cache mode: copy to USB
        info "Copying to USB..."
        if cp "$cache_file" "${usb_file}.tmp" && mv "${usb_file}.tmp" "$usb_file"; then
            ok "Copied"
            results[$fname]="OK"
            ok_count=$(( ok_count + 1 ))
        else
            err "Copy failed"
            results[$fname]="COPY_FAIL"
            fail_count=$(( fail_count + 1 ))
        fi
    done

    # === 5) Icons (skipped — no PS/HTML preview on linux) ===

    # === 6) Config files ===
    step "6/7  Writing config files"
    local theme_slug; theme_slug=$(printf '%s' "$TITLE" | tr -cs 'a-zA-Z0-9_-' '_' | tr '[:upper:]' '[:lower:]')
    generate_ventoy_json "$USB_MOUNT" "$TITLE" "$theme_slug"

    # === 7) Kali persistence ===
    if [[ $SKIP_PERSISTENCE -eq 0 ]]; then
        step "7/7  Creating Kali persistence"
        local persist_file="${USB_MOUNT}/persistence.img"
        if [[ -f "$persist_file" ]]; then
            ok "Already exists. Skipping."
        else
            info "Creating ${PERSISTENCE_MB} MB persistence image..."
            if dd if=/dev/zero of="$persist_file" bs=1M count="$PERSISTENCE_MB" status=progress 2>&1 && \
               mkfs.ext4 -L persistence "$persist_file" && \
               mkdir -p /tmp/kali_persist_mnt && \
               sudo mount "$persist_file" /tmp/kali_persist_mnt && \
               printf '/ union\n' | sudo tee /tmp/kali_persist_mnt/persistence.conf > /dev/null && \
               sudo umount /tmp/kali_persist_mnt; then
                ok "Persistence created (${PERSISTENCE_MB} MB)"
            else
                warn "Persistence creation failed"
            fi
            rmdir /tmp/kali_persist_mnt 2>/dev/null || true
        fi
    fi

    # === Summary ===
    printf "\n${BL}$(printf '=%.0s' $(seq 1 70))${RST}\n"
    printf "  ${CY}${BLD}MISSION COMPLETE${RST}\n"
    printf "${BL}$(printf '=%.0s' $(seq 1 70))${RST}\n"
    printf "  ${GR}OK=${ok_count}${RST}  ${YL}FAILED=${fail_count}${RST}  MANUAL=$(( ${#results[@]} - ok_count - fail_count ))\n\n"
    if [[ -n "$USB_MOUNT" ]]; then
        df -h "$USB_MOUNT" 2>/dev/null | tail -1 | awk '{printf "  USB free: %s / %s\n", $4, $2}'
    fi
    if [[ $fail_count -gt 0 ]]; then
        warn "To retry failed downloads:"
        printf "  bash %s -l %s -t \"%s\" -d \"%s\" -m \"%s\" -V\n\n" \
            "$(basename "$0")" "$LANGUAGE" "$TITLE" "$DOWNLOAD_DIR" "$USB_MOUNT"
    fi
    ok "USB '${TITLE}' ready at ${USB_MOUNT}"
    printf "\n"
}

main "$@"
