# Spventoy

**Multiboot USB Builder powered by [Ventoy](https://www.ventoy.net/).**
Build a single USB stick that boots Linux distros, pentest tools, sysadmin rescue ISOs, and Windows installers — all from one menu.

Two scripts, same job:
- `Build-MultibootUSB.ps1` — Windows (PowerShell 5.1+) and cross-platform via [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
- `Build-MultibootUSB.sh` — Linux (bash 4+)

Both download the latest stable versions, verify them, install Ventoy on the USB, and copy everything into a tidy folder structure with a generated `ventoy.json`.

---

## Features

- **Bilingual UI** — English and Spanish (`-Language en|es` / `-l en|es`).
- **Two download modes** — pick between **direct-to-USB** (faster, single-USB) and **cache+copy** (slower, but the cache can be reused across multiple USB builds).
- **Interactive ISO menu** — pick what you want with a live size estimate before download.
- **Always-latest version resolution** — Debian, Ubuntu, Kali, Fedora, Manjaro, TrueNAS, Ventoy itself, etc. are resolved dynamically.
- **Multi-URL fallback per ISO** — if one mirror is down, the next one is tried.
- **Resumable cache** — already-downloaded ISOs are reused; partial downloads resume (cache mode).
- **Disk-space pre-check** — refuses to start a download that won't fit.
- **Kali persistence** — optional persistent partition for Kali Live (`-PersistenceSizeMB` / `-s`).
- **Custom ISOs** — drop your own entries in `custom-isos.json`.
- **Skip-flags** — re-run the script and skip the steps already done (Ventoy install, persistence, etc.).

---

## Included ISO catalog

| Category | Examples |
|---|---|
| **Linux — Debian family** | Debian 11/12/13 (Xfce/GNOME/KDE/MATE/LXQt/LXDE), Ubuntu 20.04/22.04/24.04 (Desktop & Server), Kubuntu, Xubuntu, Lubuntu, Ubuntu MATE/Budgie/Studio, Linux Mint, MX Linux, Pop!_OS |
| **Linux — RHEL family** | Rocky Linux 8/9, AlmaLinux 8/9, Fedora Workstation, CentOS Stream 9/10, Oracle Linux 9 |
| **Linux — Arch family** | Arch Linux, EndeavourOS, Manjaro (KDE/GNOME/Xfce) |
| **Other Linux** | openSUSE Leap, openSUSE Tumbleweed |
| **Pentest & Security** | Kali Linux Live, Kali Purple SOC, Parrot Security OS, Tails |
| **Sysadmin** | Proxmox VE, TrueNAS SCALE, Clonezilla Live, GParted Live, Finnix |
| **Rescue & Recovery** | SystemRescue, Hiren's BootCD PE, MemTest86+ |
| **Windows** | Windows 10/11 (via [Fido](https://github.com/pbatard/Fido)), Windows 11 IoT Enterprise LTSC (manual) |

---

## Requirements

### Windows
- PowerShell **5.1+** (built-in) or PowerShell 7+
- Run as **Administrator** (required for Ventoy install & USB formatting)
- A USB drive of **at least 32 GB** (64 GB+ recommended if you want most of the catalog)

### Linux
- `bash` 4+, `curl`, `lsblk`, `sudo`, `tar`
- `jq` (optional, improves dynamic version resolution)
- A USB drive of **at least 32 GB**
- The block device path of your USB (e.g. `/dev/sdb`) — **double-check this**, the script will write to it

---

## Quick start

> **WARNING:** Ventoy installation **wipes the entire USB drive**. Make sure you have nothing important on it.

### Windows (PowerShell)

```powershell
# 1. Open PowerShell as Administrator
# 2. Allow script execution for this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. Run interactively (the script will prompt for everything)
.\Build-MultibootUSB.ps1
```

Or with parameters (direct-to-USB, fastest):

```powershell
.\Build-MultibootUSB.ps1 `
  -Language en `
  -Title "MYBOOT" `
  -DirectToUSB `
  -UsbDriveLetter F
```

Or with cache mode (reusable for multiple USBs):

```powershell
.\Build-MultibootUSB.ps1 `
  -Language en `
  -Title "MYBOOT" `
  -UseCache `
  -DownloadDir "D:\isos" `
  -UsbDriveLetter F
```

### Linux (bash)

```bash
# 1. Make it executable
chmod +x Build-MultibootUSB.sh

# 2. Run with sudo, direct-to-USB (fastest)
sudo ./Build-MultibootUSB.sh -l en -t MYBOOT -u -D /dev/sdb -m /media/$USER/Ventoy

# Or cache mode (reusable)
sudo ./Build-MultibootUSB.sh -l en -t MYBOOT -c -d ~/isos -D /dev/sdb -m /media/$USER/Ventoy
```

---

## Usage

### PowerShell parameters

| Parameter | Description |
|---|---|
| `-Language en\|es` | UI language (prompted if omitted) |
| `-Title <name>` | USB label / boot-menu title (e.g. `MYBOOT`) |
| `-DirectToUSB` | Download ISOs straight to the USB. Faster, no cache reuse |
| `-UseCache` | Cache ISOs to disk first, then copy to USB. Slower, but cache is reusable |
| `-DownloadDir <path>` | Directory for tooling cache (Ventoy installer, etc.). Default: `%USERPROFILE%\<Title>_cache` |
| `-UsbDriveLetter <letter>` | Windows drive letter of the Ventoy USB (e.g. `F`). Auto-detected if omitted |
| `-UsbMountPoint <path>` | (Linux/macOS) Ventoy USB mount point (e.g. `/media/user/Ventoy`) |
| `-UsbDevice <dev>` | (Linux/macOS) Block device for Ventoy install (e.g. `/dev/sdb`) |
| `-SkipPersistence` | Don't create the Kali persistence file |
| `-SkipVentoyInstall` | Don't download/run Ventoy2Disk (use this on re-runs) |
| `-PersistenceSizeMB <int>` | Kali persistence size in MB. Default: `8192` |

If neither `-DirectToUSB` nor `-UseCache` is passed, the script asks interactively.

### Bash flags

| Flag | Description |
|---|---|
| `-l en\|es` | UI language |
| `-t TITLE` | USB label / boot-menu title |
| `-u` | Direct-to-USB mode (faster, no cache reuse) |
| `-c` | Cache mode (slower, cache reusable) |
| `-d DIR` | ISO download/cache directory (used for tooling even in direct mode) |
| `-m MOUNTPOINT` | Ventoy USB mount point |
| `-D DEVICE` | Block device for Ventoy install |
| `-P` | Skip Kali persistence partition |
| `-V` | Skip Ventoy download/install |
| `-s SIZE_MB` | Kali persistence size (default: 8192) |
| `-h` | Show help |

If neither `-u` nor `-c` is passed, the script asks interactively.

---

## Adding your own ISOs

Edit `custom-isos.json` to add ISOs that aren't in the built-in catalog. Format:

```json
[
  {
    "Name":   "my-custom-os.iso",
    "Alias":  "My Custom OS",
    "Folder": "Custom",
    "SizeMB": 3000,
    "Urls": [
      "https://example.com/path/to/my-custom-os.iso",
      "https://mirror.example.com/my-custom-os.iso"
    ]
  }
]
```

- **Name** — filename to save the ISO as on the USB
- **Alias** — display name in the Ventoy boot menu
- **Folder** — subfolder under `ISO/` on the USB
- **SizeMB** — approximate size (used for the disk-space pre-check)
- **Urls** — list of download URLs (tried in order; first one that works wins)

---

## Resulting USB layout

```
<USB>/
├── ISO/
│   ├── Linux/
│   │   ├── Debian/
│   │   ├── Ubuntu/
│   │   ├── Mint/
│   │   └── ...
│   ├── Pentest/
│   ├── Sysadmin/
│   ├── Rescue/
│   ├── Windows/
│   └── Custom/
├── ventoy/
│   └── ventoy.json     ← generated automatically
└── persistence.dat     ← optional, for Kali Live
```

---

## Troubleshooting

- **"Access denied" on Windows** — the PowerShell window must be elevated (Run as Administrator).
- **Wrong USB picked** — pass `-UsbDriveLetter` (Windows) or `-UsbDevice` (Linux) explicitly. Don't trust auto-detect when you have multiple removable drives plugged in.
- **A download fails** — the script keeps going and lists the failed ISOs at the end. Re-run with `-SkipVentoyInstall` to retry only the missing ones.
- **Windows 11 LTSC** — Microsoft does not let scripts download it. The script prints the official MSDN-aggregator link and tells you where to drop the ISO afterwards.
- **Persistence not detected by Kali** — make sure the USB has enough free space for the `-PersistenceSizeMB` value, and that `SkipPersistence` is not set.

---

## How it works (under the hood)

1. **Detect environment** — Windows vs Linux, PowerShell version, available tools.
2. **Show menu** — interactive selection with running disk-space estimate.
3. **Resolve URLs** — for each selected ISO, query the project's official API/mirror list to get the latest stable version, with hard-coded fallbacks if the API fails.
4. **Download** — to the cache directory, with resume support.
5. **Install Ventoy** — downloads the latest Ventoy release, runs `Ventoy2Disk` against the chosen USB.
6. **Copy ISOs** — each into its category folder on the USB.
7. **Generate `ventoy.json`** — categorizes the boot menu by section.
8. **Create persistence** (optional) — `persistence.dat` for Kali Live with the right ext4 label.
9. **Print summary** — what succeeded, what failed, what's pending manual action.

---

## License

This project is released under the **MIT License** — see [`LICENSE`](LICENSE) for details.

The downloaded ISOs are **not** part of this repository. Each one is the property of its respective project (Debian, Ubuntu, Microsoft, etc.) and is governed by its own license.

---

## Credits

- [Ventoy](https://www.ventoy.net/) by longpanda — the actual multiboot engine.
- [Fido](https://github.com/pbatard/Fido) by Pete Batard (Rufus author) — Microsoft ISO download helper.
- All the upstream projects whose ISOs are in the catalog.
