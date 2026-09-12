# 🌿 Save Room Workspace (`start-environment`)

<div align="center">

```text
    ┌──────────────────────────────────────────────────┐
    │   ███████╗███╗   ██╗██╗   ██╗                    │
    │   ██╔════╝████╗  ██║██║   ██║   E N V I R O N    │
    │   █████╗  ██╔██╗ ██║██║   ██║                    │
    │   ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝   s t a r t u p    │
    │   ███████╗██║ ╚████║ ╚████╔╝                     │
    │   ╚══════╝╚═╝  ╚═══╝  ╚═══╝                      │
    └──────────────────────────────────────────────────┘
```

**An ambient, multi-monitor workstation bootstrapper with Resident Evil Save Room aesthetics, Wayland window tiling, and remote phone control via KDE Connect.**

[![Bash](https://img.shields.io/badge/Language-Bash%20%2F%20Python3-green.svg)](https://www.gnu.org/software/bash/)
[![Environment](https://img.shields.io/badge/Desktop-GNOME%20%7C%20Wayland%20%7C%20X11-blue.svg)](https://www.gnome.org/)
[![Remote Control](https://img.shields.io/badge/Remote%20Control-KDE%20Connect-5277c3.svg)](https://kdeconnect.kde.org/)
[![Terminal](https://img.shields.io/badge/Terminal-Ghostty-orange.svg)](https://ghostty.org/)
[![License](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

</div>

---

## ☕ The Philosophy & How I Use It

In *Resident Evil*, the **Save Room** is legendary. Amidst chaos and tension, stepping through that door brings immediate calm: soft lighting, the reassuring clack of a typewriter ribbon, and an ambient piano melody that signals sanctuary.

Modern software development often feels like survival horror — tabs piling up, context switching, broken builds.

**Save Room Workspace** automates the transition into deep work.

> **📱 How I Use It:** I control this entire setup from my phone using **KDE Connect**. When I walk into my room, I tap a single button on my phone. Before I even sit at my desk, both displays wake up, apps tile into exact mathematical grid slots across the screens, the Ghostty terminal glows in phosphor green, and my focus soundscape starts playing.

1. **Remote Phone Ignition**: Triggered directly from a phone widget/tile via **KDE Connect** (or GSConnect on GNOME).
2. **Ambient Audio**: Loops an optional ambient soundscape or focus audio track softly via `mpv` in the background.
3. **Fractional Multi-Monitor Tiling**: Mathematically slots your primary IDE, browser, AI assistant, and terminals into dedicated grid zones without accidental full-screen distortion.
4. **Retro Terminal Aesthetic**: Spawns a secondary Ghostty terminal themed in nostalgic green phosphor (`#0b0f0c` deep black background, `#d8e6c8` phosphor green text, `#7fff5a` blinking block cursor, and subtle background blur).
5. **Resilient Detached Processes**: Survives ephemeral triggers (KDE Connect / GSConnect) without being reaped by systemd.

---

## 📐 Display Architecture

Windows are placed according to calculated screen fractions rather than fixed pixel dimensions, scaling gracefully with fractional DPI scaling:

```text
  ┌─────────────────────────────────────────────────┐   ┌─────────────────────────────────────────────────┐
  │ LAPTOP DISPLAY (e.g. eDP-1)                     │   │ WORKSPACE MONITOR (e.g. HDMI-2 / DP-1)          │
  │                                                 │   │                                                 │
  │  ┌────────────────────┐ ┌────────────────────┐  │   │  ┌───────────────────────┐ ┌──────────────────┐ │
  │  │                    │ │                    │  │   │  │                       │ │  Brave Browser   │ │
  │  │  Console           │ │  Save Room         │  │   │  │  Antigravity IDE      │ │  (Upper Right)   │ │
  │  │  Terminal          │ │  Terminal          │  │   │  │  (Left Column)        │ └──────────────────┘ │
  │  │  [0.06 0.08]       │ │  [0.52 0.08]       │  │   │  │  [0.02 0.05]          │ ┌──────────────────┐ │
  │  │  (Neutral Grey)    │ │  (Green Phosphor)  │  │   │  │                       │ │  Claude Desktop  │ │
  │  │                    │ │                    │  │   │  │                       │ │  (Lower Right)   │ │
  │  └────────────────────┘ └────────────────────┘  │   │  └───────────────────────┘ └──────────────────┘ │
  └─────────────────────────────────────────────────┘   └─────────────────────────────────────────────────┘
```

> **Single-Monitor Fallback**: When traveling or disconnected from external screens, the engine automatically detects single-monitor mode and switches to a compact layout so windows never swallow each other.

---

## 🛠️ The Technical Challenges & Engineering Feats

Automating modern Linux desktop environments (especially GNOME on Wayland) involves overcoming severe compositor security restrictions. Here is how this project solves them:

### 1. The Wayland Window Placement Limitation
Wayland's security protocol deliberately disallows client applications from manipulating or querying other windows. GNOME's Mutter compositor does not provide an external window management API.

* **Solution**: The script leverages an XWayland bridge (`GDK_BACKEND=x11`). It queries Mutter's logical monitor geometries via DBus (`org.gnome.Mutter.DisplayConfig`), reconciles monitor scaling factors, and uses `GdkX11.X11Window.foreign_new_for_display` to directly reposition and resize windows asynchronously with zero external packages.

### 2. Escaping Systemd's Transient Scope Reaper
When triggered from a smartphone via **GSConnect** or **KDE Connect**, commands run inside ephemeral transient systemd scopes (`app-ghostty-surface-transient-*.scope`) configured with `KillMode=control-group`.
Standard tricks like `nohup`, `disown`, or `setsid` only detach the process from the shell session — **not the cgroup**. When the trigger window closes, systemd reaps all child processes.

* **Solution**: Every spawned app and daemon is prefixed with `systemd-run --user --scope --quiet --collect --`, carving out an independent scope so the entire workspace outlives the triggering mechanism.

### 3. Asynchronous Non-Blocking Placement
Applications have widely varying startup latencies (e.g. Electron apps vs native terminals). Sequential placement stalls the boot process.

* **Solution**: Window discovery and positioning jobs run asynchronously in parallel (`place_async`), waiting concurrently up to a deadline. A fallback loop checks client lists by `WM_CLASS` regex to ensure robust placement as windows map.

---

## 🚀 Quickstart

### Prerequisites

Install standard system tools available on all major distributions:

```bash
# Ubuntu / Debian / Pop!_OS
sudo apt update && sudo apt install -y python3-gi gir1.2-gtk-3.0 x11-utils mpv ghostty

# Fedora
sudo dnf install -y python3-gobject gtk3 xorg-x11-utils mpv ghostty

# Arch Linux
sudo pacman -S python-gobject gtk3 xorg-xprop mpv ghostty
```

### Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/ZakariaElkhadir/save-room-workspace.git
cd save-room-workspace
./install.sh
```

This installs:
* `start-environment` in `~/.local/bin/`
* `Start Work Environment` desktop entry in your application launcher
* Initial configuration template in `~/.config/start-environment/config.env`

---

## 🎛️ Configuration

Create or edit your user configuration:

```bash
nano ~/.config/start-environment/config.env
```

```bash
# Display connector targets (auto-detected if unset)
CONSOLE_DISPLAY="eDP-1"
WORKSPACE_DISPLAY="HDMI-2"

# Optional ambient audio track or soundscape (leave empty to disable)
AUDIO_FILE=""
AUDIO_VOLUME=100

# Applications
IDE_CMD="antigravity-ide"
BRAVE_CMD="brave-browser-stable"
CLAUDE_CMD="claude-desktop"
TERMINAL_CMD="ghostty"
```

---

## 📱 Remote Phone Control via KDE Connect / GSConnect

The centerpiece of my daily workflow is remote phone ignition. Instead of manually opening apps and moving windows with a mouse, I trigger the entire workspace boot sequence straight from my phone over the local network using **KDE Connect** (or **GSConnect** on GNOME):

### How I Set It Up:
1. Pair your phone (Android / iOS) with your workstation using **KDE Connect** (or **GSConnect** for GNOME).
2. On your Linux desktop, open KDE Connect / GSConnect settings.
3. Under **Run Commands**, add a new entry:
   * **Name**: `Start Work Environment`
   * **Command**: `start-environment` (or `~/start-environement.sh`)
4. On your phone:
   * Add a **KDE Connect "Run Command" widget** to your phone's home screen, or add it as an **Android Quick Settings pull-down tile**.
   * One tap triggers the entire sequence: displays wake, windows tile with mathematical accuracy, Ghostty console launches with CRT theme, and focus audio begins looping.
5. **The Secret Sauce**: Ephemeral mobile commands run inside transient systemd scopes. This script wraps launches in `systemd-run --user --scope` so your workspace outlives the mobile trigger lifecycle.

---

## 📖 CLI Commands

```bash
start-environment                   # Boot the complete workspace
start-environment --no-audio        # Launch applications without audio (alias: --no-music)
start-environment --audio-only      # Play ambient audio only (alias: --music-only)
start-environment --stop-audio      # Stop ambient audio (alias: --stop)
start-environment --status          # Show running status & connected displays
start-environment --layout          # Re-apply window layout to running windows
start-environment --single-screen   # Force single-monitor adaptive layout
start-environment --config          # Print active configuration
start-environment --help            # Show usage
```

---

## 📜 License

Distributed under the [MIT License](LICENSE). Built with passion by [Zakaria Elkhadir](https://github.com/ZakariaElkhadir).
