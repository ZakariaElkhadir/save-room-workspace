#!/usr/bin/env bash
#
#  start-environment.sh — ambient multi-monitor workstation bootstrapper
#  Antigravity IDE · Brave · Ghostty (console + Save Room) · Claude Desktop
#  looping soundtrack · windows split across displays with fractional tiling
#
#  Usage:
#     ./start-environment.sh                 launch everything
#     ./start-environment.sh --no-audio      launch apps without audio (alias: --no-music)
#     ./start-environment.sh --audio-only    just play ambient audio (alias: --music-only)
#     ./start-environment.sh --stop-audio    stop ambient audio (alias: --stop)
#     ./start-environment.sh --status        what is currently running
#     ./start-environment.sh --layout        re-apply window layout only
#     ./start-environment.sh --single-screen force single-screen layout
#     ./start-environment.sh --config        display active configuration
#     ./start-environment.sh --help          show usage and options
#

set -uo pipefail

VERSION="2.1.0"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# ─────────────────────────────  configuration  ─────────────────────────────

# Default user greeting
SESSION_USER="${SESSION_USER:-${USER^}}"

# Ambient audio / soundtrack (AUDIO_FILE takes precedence over MUSIC_FILE; optional)
AUDIO_FILE="${AUDIO_FILE:-${MUSIC_FILE:-}}"
AUDIO_VOLUME="${AUDIO_VOLUME:-${MUSIC_VOLUME:-100}}" # 0-100
LAUNCH_DELAY="${LAUNCH_DELAY:-1.0}"                  # seconds between app launches

# Target display connectors (auto-detected if unset or not present)
CONSOLE_DISPLAY="${CONSOLE_DISPLAY:-eDP-1}"    # laptop panel  — console + Save Room
WORKSPACE_DISPLAY="${WORKSPACE_DISPLAY:-HDMI-2}" # HP E243i      — application windows
CONSOLE_LABEL="${CONSOLE_LABEL:-laptop}"
WORKSPACE_LABEL="${WORKSPACE_LABEL:-HP screen}"

# Window layout (Dual-Screen mode) as fractions of display: x y width height
LAYOUT_CONSOLE="${LAYOUT_CONSOLE:-0.06 0.08 0.42 0.82}"   # Ghostty console  — laptop, left half
LAYOUT_SAVEROOM="${LAYOUT_SAVEROOM:-0.52 0.08 0.42 0.82}" # Save Room term   — laptop, right half
LAYOUT_IDE="${LAYOUT_IDE:-0.02 0.05 0.58 0.88}"           # Antigravity      — external, left column
LAYOUT_BROWSER="${LAYOUT_BROWSER:-0.62 0.05 0.36 0.53}"   # Brave            — external, upper right
LAYOUT_CLAUDE="${LAYOUT_CLAUDE:-0.62 0.60 0.36 0.33}"    # Claude           — external, lower right

# Window layout (Single-Screen fallback mode)
SINGLE_LAYOUT_CONSOLE="${SINGLE_LAYOUT_CONSOLE:-0.02 0.05 0.40 0.44}"
SINGLE_LAYOUT_SAVEROOM="${SINGLE_LAYOUT_SAVEROOM:-0.02 0.52 0.40 0.42}"
SINGLE_LAYOUT_IDE="${SINGLE_LAYOUT_IDE:-0.44 0.05 0.54 0.89}"
SINGLE_LAYOUT_BROWSER="${SINGLE_LAYOUT_BROWSER:-0.44 0.05 0.54 0.50}"
SINGLE_LAYOUT_CLAUDE="${SINGLE_LAYOUT_CLAUDE:-0.44 0.57 0.54 0.37}"

# Application commands
IDE_CMD="${IDE_CMD:-antigravity-ide}"
BRAVE_CMD="${BRAVE_CMD:-brave-browser-stable}"
CLAUDE_CMD="${CLAUDE_CMD:-claude-desktop}"
TERMINAL_CMD="${TERMINAL_CMD:-ghostty}"

# Load user configuration override if available
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/start-environment"
GLOBAL_CONFIG="$CONFIG_DIR/config.env"
LOCAL_CONFIG="$SCRIPT_DIR/config.env"

if [[ -n "${ENV_CONFIG:-}" && -f "$ENV_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_CONFIG"
elif [[ -f "$GLOBAL_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$GLOBAL_CONFIG"
elif [[ -f "$LOCAL_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$LOCAL_CONFIG"
fi

# Reconcile audio variables (AUDIO_FILE takes priority over legacy MUSIC_FILE)
AUDIO_FILE="${AUDIO_FILE:-${MUSIC_FILE:-}}"
AUDIO_VOLUME="${AUDIO_VOLUME:-${MUSIC_VOLUME:-100}}"

# Resolve binary aliases across distributions
resolve_cmd() {
  local preferred="$1"
  shift
  if command -v "$preferred" >/dev/null 2>&1; then
    echo "$preferred"
    return 0
  fi
  for alt in "$@"; do
    if command -v "$alt" >/dev/null 2>&1; then
      echo "$alt"
      return 0
    fi
  done
  echo "$preferred"
  return 1
}

IDE_CMD=$(resolve_cmd "$IDE_CMD" code cursor)
BRAVE_CMD=$(resolve_cmd "$BRAVE_CMD" brave-browser brave)
CLAUDE_CMD=$(resolve_cmd "$CLAUDE_CMD" claude)
TERMINAL_CMD=$(resolve_cmd "$TERMINAL_CMD" ghostty gnome-terminal alacritty kitty)

# ─────────────────────────────  boot diagnostics  ───────────────────────────
# Records execution details to a stable log path to diagnose ephemeral launches
# (e.g. GSConnect/KDE Connect phone shortcuts). Automatically rotates if > 512KB.
DEBUG_LOG="${DEBUG_LOG:-$HOME/.cache/start-environment-debug.log}"
mkdir -p "$(dirname "$DEBUG_LOG")" 2>/dev/null

if [[ -f "$DEBUG_LOG" && $(wc -c <"$DEBUG_LOG" 2>/dev/null || echo 0) -gt 524288 ]]; then
  tail -n 300 "$DEBUG_LOG" >"$DEBUG_LOG.tmp" 2>/dev/null && mv "$DEBUG_LOG.tmp" "$DEBUG_LOG"
fi

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S.%N' | cut -c1-23) pid=$$ ppid=$PPID args=[$*] ==="
  echo "DISPLAY=${DISPLAY:-<unset>}"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<unset>}"
  echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-<unset>}"
  echo "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-<unset>}"
  echo "GDK_BACKEND=${GDK_BACKEND:-<unset>}"
  echo "ENVSTART_X11=${ENVSTART_X11:-<unset>}"
  echo "HOME=${HOME:-<unset>} PATH=${PATH:-<unset>}"
  if command -v systemd-run >/dev/null 2>&1; then
    if out=$(systemd-run --user --scope --quiet --collect -- true 2>&1); then
      echo "systemd-run self-test: OK"
    else
      echo "systemd-run self-test: FAILED rc=$? out=[$out]"
    fi
  else
    echo "systemd-run self-test: not found on PATH"
  fi
  if command -v "$TERMINAL_CMD" >/dev/null 2>&1; then
    echo "terminal binary ($TERMINAL_CMD): $(command -v "$TERMINAL_CMD")"
  else
    echo "terminal binary ($TERMINAL_CMD): NOT FOUND"
  fi
} >>"$DEBUG_LOG" 2>&1

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/start-environment"
PID_FILE="$RUNTIME_DIR/music.pid"
LOG_DIR="$RUNTIME_DIR/logs"
WM_HELPER="$RUNTIME_DIR/wm.py"
CONSOLE_TITLE="ENV CONSOLE"
SAVEROOM_TITLE="SAVE ROOM"

mkdir -p "$LOG_DIR"

# Ghostty look for this console — kept plain/neutral.
GHOSTTY_ARGS=(
  --gtk-single-instance=false
  --title="$CONSOLE_TITLE"
)

# Ghostty look for the second terminal — the RE4 "Save Room" aesthetic:
# deep green-black background, pale phosphor green text, blinking amber-green cursor.
SAVEROOM_ARGS=(
  --gtk-single-instance=false
  --background=#0b0f0c
  --foreground=#d8e6c8
  --cursor-color=#7fff5a
  --cursor-style=block
  --cursor-style-blink=true
  --selection-background=#1f3d1a
  --selection-foreground=#eaffe0
  --background-opacity=0.94
  --background-blur=true
  --window-padding-x=14
  --window-padding-y=12
  --font-size=12
  --title="$SAVEROOM_TITLE"
)

# ─────────────────────────────  palette / output  ──────────────────────────

if [[ -t 1 ]]; then
  R=$'\e[0m'
  B=$'\e[1m'
  DIM=$'\e[2m'
  GRN=$'\e[38;5;77m'
  AMB=$'\e[38;5;179m'
  RED=$'\e[38;5;167m'
  CYA=$'\e[38;5;80m'
  GRY=$'\e[38;5;244m'
  WHT=$'\e[38;5;231m'
else
  R= B= DIM= GRN= AMB= RED= CYA= GRY= WHT=
fi

banner() {
  printf '%s\n' "${GRN}${B}"
  cat <<'ART'
    ┌──────────────────────────────────────────────────┐
    │   ███████╗███╗   ██╗██╗   ██╗                    │
    │   ██╔════╝████╗  ██║██║   ██║   E N V I R O N    │
    │   █████╗  ██╔██╗ ██║██║   ██║                    │
    │   ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝   s t a r t u p    │
    │   ███████╗██║ ╚████║ ╚████╔╝                     │
    │   ╚══════╝╚═╝  ╚═══╝  ╚═══╝                      │
    └──────────────────────────────────────────────────┘
ART
  printf '%s' "$R"
  printf '        %s%s\n\n' "${GRY}" "$(date '+%A %d %B %Y · %H:%M')${R}"
}

step() { printf '  %s▸%s %-22s' "${CYA}" "${R}" "$1"; }
ok()   { printf '%s[  OK  ]%s %s%s%s\n' "${GRN}" "$R" "$DIM" "${1:-}" "$R"; }
skip() { printf '%s[ SKIP ]%s %s%s%s\n' "${AMB}" "$R" "$DIM" "${1:-}" "$R"; }
fail() { printf '%s[ FAIL ]%s %s%s%s\n' "${RED}" "$R" "$DIM" "${1:-}" "$R"; }
info() { printf '  %s·%s %s\n' "${GRY}" "$R" "$1"; }
rule() { printf '  %s%s%s\n' "$GRY" "────────────────────────────────────────────────" "$R"; }

# ─────────────────────────────  argument parsing  ──────────────────────────

MODE="all"
RELAUNCH=1
FORCE_SINGLE_SCREEN=0

for a in "$@"; do
  case "$a" in
  --no-audio | --no-music)     MODE="apps" ;;
  --audio-only | --music-only) MODE="audio"; RELAUNCH=0 ;;
  --stop-audio | --stop)       MODE="stop";  RELAUNCH=0 ;;
  --status)        MODE="status"; RELAUNCH=0 ;;
  --layout)        MODE="layout"; RELAUNCH=0 ;;
  --single-screen) FORCE_SINGLE_SCREEN=1 ;;
  --config)        MODE="config"; RELAUNCH=0 ;;
  --here)          RELAUNCH=0 ;;
  -v | --version)
    echo "start-environment v$VERSION"
    exit 0
    ;;
  -h | --help)
    MODE="help"
    RELAUNCH=0
    ;;
  *)
    printf '%s✗ Unknown option: %s%s\n' "$RED" "$a" "$R"
    echo "Run with --help to see available options."
    exit 1
    ;;
  esac
done

# ─────────────────────────────  cgroup escape  ─────────────────────────────
# In systemd user sessions, transient scopes (such as those created when a
# command is triggered via KDE Connect or GSConnect) have KillMode=control-group.
# Plain setsid/disown detaches from the session, but leaves children inside
# the dying cgroup.
# `systemd-run --user --scope` places the process in its own dedicated scope
# so it outlives the caller.
if command -v systemd-run >/dev/null 2>&1; then
  DETACH_PREFIX=(systemd-run --user --scope --quiet --collect --)
else
  DETACH_PREFIX=()
fi

# ─────────────────────────────  X11 relaunch  ──────────────────────────────
# GTK4 / native Wayland does not expose programmatic foreign window placement.
# We re-enter inside an XWayland terminal so the layout manager (GdkX11)
# can discover and precisely position all managed windows.
if [[ "$RELAUNCH" == "1" && -z "${ENVSTART_X11:-}" && "${GDK_BACKEND:-}" != "x11" ]]; then
  if command -v "$TERMINAL_CMD" >/dev/null 2>&1; then
    echo "RELAUNCHING: $(date '+%H:%M:%S.%N' | cut -c1-12) -> ${DETACH_PREFIX[*]} $TERMINAL_CMD ${GHOSTTY_ARGS[*]} -e $SCRIPT_PATH $*" >>"$DEBUG_LOG" 2>&1
    ENVSTART_X11=1 GDK_BACKEND=x11 setsid nohup \
      "${DETACH_PREFIX[@]}" "$TERMINAL_CMD" "${GHOSTTY_ARGS[@]}" -e "$SCRIPT_PATH" "$@" \
      >>"$DEBUG_LOG" 2>&1 </dev/null &
    RLPID=$!
    disown 2>/dev/null
    echo "RELAUNCH backgrounded as pid=$RLPID, exiting now" >>"$DEBUG_LOG" 2>&1
    exit 0
  else
    echo "RELAUNCH skipped: $TERMINAL_CMD not found on PATH" >>"$DEBUG_LOG" 2>&1
  fi
else
  echo "RELAUNCH skipped: RELAUNCH=$RELAUNCH ENVSTART_X11=${ENVSTART_X11:-<unset>} GDK_BACKEND=${GDK_BACKEND:-<unset>}" >>"$DEBUG_LOG" 2>&1
fi

# ─────────────────────────────  window manager helper  ─────────────────────
# Embedded python helper using system GdkX11 and Mutter DisplayConfig DBus.
# No pip dependencies required.

write_wm_helper() {
  cat >"$WM_HELPER" <<'PY_EOF'
#!/usr/bin/env python3
"""Place XWayland windows on a chosen monitor. Needs no extra packages."""
import os, re, sys, time, subprocess, argparse

os.environ["GDK_BACKEND"] = "x11"
import gi
gi.require_version("Gdk", "3.0")
gi.require_version("GdkX11", "3.0")
from gi.repository import Gdk, GdkX11, Gio

_DISPLAY = None


def x11_display():
    """Gdk needs an explicitly opened X11 display when nothing else has."""
    global _DISPLAY
    if _DISPLAY is None:
        _DISPLAY = Gdk.Display.get_default() or \
                   Gdk.Display.open(os.environ.get("DISPLAY", ":0"))
    return _DISPLAY


def monitors():
    """connector -> (x, y, width, height, is_primary) via Mutter DBus with xrandr fallback."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        res = bus.call_sync(
            "org.gnome.Mutter.DisplayConfig", "/org/gnome/Mutter/DisplayConfig",
            "org.gnome.Mutter.DisplayConfig", "GetCurrentState",
            None, None, Gio.DBusCallFlags.NONE, 2000, None)
        _serial, phys, logical, _props = res.unpack()

        modes = {}
        for (connector, *_ids), mode_list, _p in phys:
            for _id, w, h, _r, _ps, _sup, flags in mode_list:
                if flags.get("is-current"):
                    modes[connector] = (w, h)
                    break

        out = {}
        for x, y, scale, _transform, _primary, mons, _p in logical:
            for connector, *_rest in mons:
                w, h = modes.get(connector, (0, 0))
                out[connector] = (int(x), int(y), int(w / scale), int(h / scale), 1 if _primary else 0)
        if out:
            return out
    except Exception:
        pass

    try:
        raw = subprocess.run(["xrandr", "--current"], capture_output=True, text=True, timeout=3).stdout
        out = {}
        for line in raw.splitlines():
            m = re.match(r"^(\S+)\s+connected\s+(?:(primary)\s+)?(\d+)x(\d+)\+(\d+)\+(\d+)", line)
            if m:
                conn, prim, w, h, x, y = m.groups()
                out[conn] = (int(x), int(y), int(w), int(h), 1 if prim else 0)
        return out
    except Exception:
        return {}


def clients():
    """[(xid, wm_class, title)] for every managed toplevel."""
    try:
        raw = subprocess.run(["xprop", "-root", "_NET_CLIENT_LIST"],
                             capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return []
    ids = re.findall(r"0x[0-9a-fA-F]+", raw)
    found = []
    for xid in ids:
        try:
            p = subprocess.run(["xprop", "-id", xid, "WM_CLASS", "_NET_WM_NAME", "WM_NAME"],
                               capture_output=True, text=True, timeout=5).stdout
        except Exception:
            continue
        cls = " ".join(re.findall(r'"([^"]*)"',
              next((l for l in p.splitlines() if l.startswith("WM_CLASS")), "")))
        name = ""
        for key in ("_NET_WM_NAME", "WM_NAME"):
            line = next((l for l in p.splitlines() if l.startswith(key)), "")
            m = re.search(r'"(.*)"', line)
            if m:
                name = m.group(1)
                break
        found.append((int(xid, 16), cls, name))
    return found


def place(xid, x, y, w, h):
    display = x11_display()
    if display is None:
        print("cannot open X display", file=sys.stderr)
        return False
    win = GdkX11.X11Window.foreign_new_for_display(display, xid)
    if win is None:
        return False
    try:
        win.unfullscreen()
        win.unmaximize()
    except Exception:
        pass
    Gdk.flush()
    time.sleep(0.25)
    win.move_resize(int(x), int(y), int(w), int(h))
    Gdk.flush()
    time.sleep(0.35)
    win.move_resize(int(x), int(y), int(w), int(h))
    Gdk.flush()
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["monitors", "place"])
    ap.add_argument("--wclass", default="")
    ap.add_argument("--title", default="")
    ap.add_argument("--display", default="")
    ap.add_argument("--frac", default="")
    ap.add_argument("--timeout", type=float, default=15.0)
    args = ap.parse_args()

    mons = monitors()

    if args.command == "monitors":
        for name, data in sorted(mons.items()):
            x, y, w, h = data[0], data[1], data[2], data[3]
            is_prim = data[4] if len(data) > 4 else 0
            print(f"{name} {x} {y} {w} {h} {is_prim}")
        return 0

    if args.display not in mons:
        if not mons:
            print("no monitors", file=sys.stderr)
            return 1
        args.display = max(mons, key=lambda k: mons[k][2] * mons[k][3])

    mx, my, mw, mh = mons[args.display][:4]
    fx, fy, fw, fh = (float(v) for v in args.frac.split())
    x, y = int(mx + fx * mw), int(my + fy * mh)
    w, h = int(fw * mw), int(fh * mh)

    cls_re = re.compile(args.wclass, re.IGNORECASE) if args.wclass else None
    ttl_re = re.compile(args.title, re.IGNORECASE) if args.title else None
    if cls_re is None and ttl_re is None:
        print("need --wclass or --title", file=sys.stderr)
        return 2

    deadline = time.time() + args.timeout
    while time.time() < deadline:
        for xid, cls, title in clients():
            if cls_re and not cls_re.search(cls):
                continue
            if ttl_re and not ttl_re.search(title):
                continue
            if place(xid, x, y, w, h):
                print(f"{args.display} {x},{y} {w}x{h}")
                return 0
        time.sleep(0.4)
    print("window not found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
PY_EOF
  chmod +x "$WM_HELPER"
}

# ─────────────────────────────  monitor detection  ─────────────────────────

IS_SINGLE_SCREEN=0

detect_displays() {
  write_wm_helper
  local detected=()
  local prim=""
  local externals=()

  while read -r name x y w h is_prim; do
    detected+=("$name")
    if [[ "$is_prim" == "1" || "$name" =~ ^(eDP|LVDS) ]]; then
      [[ -z "$prim" ]] && prim="$name"
    else
      externals+=("$name")
    fi
  done < <(GDK_BACKEND=x11 python3 "$WM_HELPER" monitors 2>/dev/null)

  if ((${#detected[@]} == 0)); then
    return 0
  fi

  # Validate or fallback CONSOLE_DISPLAY
  if [[ ! " ${detected[*]} " =~ " ${CONSOLE_DISPLAY} " ]]; then
    CONSOLE_DISPLAY="${prim:-${detected[0]}}"
  fi

  # Validate or fallback WORKSPACE_DISPLAY
  if [[ "$FORCE_SINGLE_SCREEN" == "1" || ${#detected[@]} -le 1 ]]; then
    IS_SINGLE_SCREEN=1
    WORKSPACE_DISPLAY="$CONSOLE_DISPLAY"
    WORKSPACE_LABEL="primary"
  else
    IS_SINGLE_SCREEN=0
    if [[ ! " ${detected[*]} " =~ " ${WORKSPACE_DISPLAY} " ]]; then
      if ((${#externals[@]} > 0)); then
        WORKSPACE_DISPLAY="${externals[0]}"
        WORKSPACE_LABEL="external (${WORKSPACE_DISPLAY})"
      else
        WORKSPACE_DISPLAY="$CONSOLE_DISPLAY"
        IS_SINGLE_SCREEN=1
        WORKSPACE_LABEL="primary"
      fi
    fi
  fi
}

# ─────────────────────────────  window placement  ──────────────────────────

FAULTS=0
PLACE_TIMEOUT=15

place_async() {
  local out="$1" wclass="$2" title="$3" disp="$4" frac="$5"
  GDK_BACKEND=x11 python3 "$WM_HELPER" place \
    --wclass "$wclass" --title "$title" \
    --display "$disp" --frac "$frac" \
    --timeout "$PLACE_TIMEOUT" 2>>"$LOG_DIR/wm.log" >"$out"
}

report_place() {
  local label="$1" out="$2" proc="${3:-}" result=""
  [[ -f "$out" ]] && result=$(<"$out")
  step "$label"
  if [[ -n "$result" ]]; then
    ok "$result"
    return 0
  fi
  FAULTS=$((FAULTS + 1))
  if [[ -n "$proc" ]] && pgrep -f "$proc" >/dev/null 2>&1; then
    fail "running on Wayland"
    info "started outside this script — quit it and re-run to place it"
  else
    fail "no window found"
  fi
}

apply_layout() {
  printf '  %s%sWINDOW LAYOUT%s\n' "$B" "$WHT" "$R"
  rule
  detect_displays

  local tmp
  tmp=$(mktemp -d "$RUNTIME_DIR/layout.XXXXXX")

  if ((IS_SINGLE_SCREEN == 1)); then
    info "Single display active ($CONSOLE_DISPLAY) — applying adaptive layout"
    place_async "$tmp/console" "$TERMINAL_CMD" "$CONSOLE_TITLE" \
      "$CONSOLE_DISPLAY" "$SINGLE_LAYOUT_CONSOLE" &
    place_async "$tmp/saveroom" "$TERMINAL_CMD" "$SAVEROOM_TITLE" \
      "$CONSOLE_DISPLAY" "$SINGLE_LAYOUT_SAVEROOM" &
    place_async "$tmp/ide" "$IDE_CMD" "" \
      "$CONSOLE_DISPLAY" "$SINGLE_LAYOUT_IDE" &
    place_async "$tmp/brave" "brave" "" \
      "$CONSOLE_DISPLAY" "$SINGLE_LAYOUT_BROWSER" &
    place_async "$tmp/claude" "anthropic|claude-desktop" "" \
      "$CONSOLE_DISPLAY" "$SINGLE_LAYOUT_CLAUDE" &
    wait

    report_place "console → $CONSOLE_LABEL" "$tmp/console" "$TERMINAL_CMD"
    report_place "Save Room → $CONSOLE_LABEL" "$tmp/saveroom" "$TERMINAL_CMD"
    report_place "IDE → $WORKSPACE_LABEL" "$tmp/ide" "$IDE_CMD"
    report_place "Brave → $WORKSPACE_LABEL" "$tmp/brave" "$BRAVE_CMD"
    report_place "Claude → $WORKSPACE_LABEL" "$tmp/claude" "$CLAUDE_CMD"
  else
    place_async "$tmp/console" "$TERMINAL_CMD" "$CONSOLE_TITLE" \
      "$CONSOLE_DISPLAY" "$LAYOUT_CONSOLE" &
    place_async "$tmp/saveroom" "$TERMINAL_CMD" "$SAVEROOM_TITLE" \
      "$CONSOLE_DISPLAY" "$LAYOUT_SAVEROOM" &
    place_async "$tmp/ide" "$IDE_CMD" "" \
      "$WORKSPACE_DISPLAY" "$LAYOUT_IDE" &
    place_async "$tmp/brave" "brave" "" \
      "$WORKSPACE_DISPLAY" "$LAYOUT_BROWSER" &
    place_async "$tmp/claude" "anthropic|claude-desktop" "" \
      "$WORKSPACE_DISPLAY" "$LAYOUT_CLAUDE" &
    wait

    report_place "console → $CONSOLE_LABEL" "$tmp/console" "$TERMINAL_CMD"
    report_place "Save Room → $CONSOLE_LABEL" "$tmp/saveroom" "$TERMINAL_CMD"
    report_place "IDE → $WORKSPACE_LABEL" "$tmp/ide" "$IDE_CMD"
    report_place "Brave → $WORKSPACE_LABEL" "$tmp/brave" "$BRAVE_CMD"
    report_place "Claude → $WORKSPACE_LABEL" "$tmp/claude" "$CLAUDE_CMD"
  fi

  rm -rf "$tmp"
  printf '\n'
}

# ─────────────────────────────  launching  ─────────────────────────────────

spawn() {
  local name="$1"
  shift
  GDK_BACKEND=x11 setsid nohup "${DETACH_PREFIX[@]}" "$@" \
    >"$LOG_DIR/${name}.log" 2>&1 </dev/null &
  disown 2>/dev/null
}

launch() {
  local label="$1" pattern="$2"
  shift 2
  step "$label"
  if ! command -v "$1" >/dev/null 2>&1 && [[ ! -x "$1" ]]; then
    fail "not installed"
    return 1
  fi
  if [[ -n "$pattern" ]] && pgrep -f "$pattern" >/dev/null 2>&1; then
    skip "already running"
    return 0
  fi
  spawn "$label" "$@"
  sleep "$LAUNCH_DELAY"
  ok "launched"
}

# ─────────────────────────────  soundtrack  ────────────────────────────────

audio_pid() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid=$(<"$PID_FILE")
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && {
    printf '%s' "$pid"
    return 0
  }
  rm -f "$PID_FILE"
  return 1
}

# Alias for backwards compatibility
music_pid() { audio_pid; }

start_audio() {
  # Strictly optional: silently skip if empty, unset, or file does not exist
  if [[ -z "${AUDIO_FILE:-}" || ! -f "$AUDIO_FILE" ]]; then
    return 0
  fi
  if ! command -v mpv >/dev/null 2>&1; then
    return 0
  fi

  step "soundtrack"

  local pid
  if pid=$(audio_pid); then
    if grep -qz -- "--volume=$AUDIO_VOLUME" "/proc/$pid/cmdline" 2>/dev/null; then
      skip "already playing"
      return 0
    fi
    kill "$pid" 2>/dev/null
    sleep 0.3
    rm -f "$PID_FILE"
  fi

  setsid nohup "${DETACH_PREFIX[@]}" mpv \
    --loop-file=inf \
    --no-video \
    --no-terminal \
    --really-quiet \
    --volume="$AUDIO_VOLUME" \
    --audio-display=no \
    "$AUDIO_FILE" \
    >"$LOG_DIR/music.log" 2>&1 </dev/null &

  pid=$!
  disown 2>/dev/null
  echo "$pid" >"$PID_FILE"

  sleep 0.6
  if kill -0 "$pid" 2>/dev/null; then
    ok "looping · vol ${AUDIO_VOLUME}%"
    info "$(basename "$AUDIO_FILE")"
  else
    rm -f "$PID_FILE"
    return 0
  fi
}

start_music() { start_audio; }

stop_audio() {
  step "soundtrack"
  local pid
  if pid=$(audio_pid); then
    kill "$pid" 2>/dev/null
    sleep 0.3
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    rm -f "$PID_FILE"
    ok "stopped"
  else
    skip "not playing"
  fi
}

stop_music() { stop_audio; }

notify() {
  command -v notify-send >/dev/null 2>&1 &&
    notify-send -a "Environment" -i utilities-terminal "$1" "${2:-}" 2>/dev/null
  return 0
}

# ─────────────────────────────  cli displays  ──────────────────────────────

show_status() {
  banner
  printf '  %s%sSTATUS%s\n' "$B" "$WHT" "$R"
  rule
  local pairs=(
    "IDE ($IDE_CMD):$IDE_CMD"
    "Brave Browser:brave"
    "Ghostty console:$TERMINAL_CMD"
    "Save Room terminal:$SAVEROOM_TITLE"
    "Claude Desktop:claude"
  )
  for p in "${pairs[@]}"; do
    step "${p%%:*}"
    if pgrep -f "${p##*:}" >/dev/null 2>&1; then ok "running"; else skip "stopped"; fi
  done
  step "soundtrack"
  if pid=$(audio_pid); then
    ok "playing (pid $pid)"
  elif [[ -n "${AUDIO_FILE:-}" && -f "$AUDIO_FILE" ]]; then
    skip "silent"
  else
    skip "disabled"
  fi
  printf '\n'

  printf '  %s%sDISPLAYS%s\n' "$B" "$WHT" "$R"
  rule
  detect_displays
  GDK_BACKEND=x11 python3 "$WM_HELPER" monitors 2>/dev/null | while read -r n x y w h is_prim; do
    tag=""
    [[ "$n" == "$CONSOLE_DISPLAY" ]] && tag=" ← $CONSOLE_LABEL / console"
    [[ "$n" == "$WORKSPACE_DISPLAY" && "$n" != "$CONSOLE_DISPLAY" ]] && tag=" ← $WORKSPACE_LABEL / apps"
    info "$(printf '%-8s %sx%s at %s,%s%s' "$n" "$w" "$h" "$x" "$y" "$tag")"
  done
  printf '\n'
}

show_config() {
  banner
  printf '  %s%sACTIVE CONFIGURATION%s\n' "$B" "$WHT" "$R"
  rule
  info "Session User:        $SESSION_USER"
  info "Audio File:          ${AUDIO_FILE:-<disabled>}"
  info "Audio Volume:        ${AUDIO_VOLUME}%"
  info "Console Display:     $CONSOLE_DISPLAY ($CONSOLE_LABEL)"
  info "Workspace Display:   $WORKSPACE_DISPLAY ($WORKSPACE_LABEL)"
  info "IDE Command:         $IDE_CMD"
  info "Browser Command:     $BRAVE_CMD"
  info "Claude Command:      $CLAUDE_CMD"
  info "Terminal Command:    $TERMINAL_CMD"
  info "Config search path:  $GLOBAL_CONFIG, $LOCAL_CONFIG"
  printf '\n'
}

usage() {
  banner
  sed -n '7,18p' "$0" | sed 's/^#\s\?//' | sed "s/^/  ${GRY}/;s/$/${R}/"
  printf '\n'
}

# ─────────────────────────────  main  ──────────────────────────────────────

case "$MODE" in
help)
  usage
  exit 0
  ;;
config)
  show_config
  exit 0
  ;;
status)
  show_status
  exit 0
  ;;
stop)
  banner
  printf '  %s%sSHUTTING DOWN AUDIO%s\n' "$B" "$WHT" "$R"
  rule
  stop_audio
  printf '\n'
  exit 0
  ;;
layout)
  banner
  apply_layout
  printf '  %s%s✔ Layout applied.%s\n\n' "$B" "$GRN" "$R"
  exit 0
  ;;
esac

banner
printf '  %s%sBOOTING ENVIRONMENT%s\n' "$B" "$WHT" "$R"
rule

detect_displays

if [[ "$MODE" != "audio" && "$MODE" != "music" ]]; then
  launch "Main IDE" "$IDE_CMD" "$IDE_CMD"
  launch "Brave" "brave-browser|brave" "$BRAVE_CMD" --ozone-platform=x11
  launch "Claude Desktop" "claude" "$CLAUDE_CMD" --ozone-platform=x11
  launch "Save Room" "$SAVEROOM_TITLE" "$TERMINAL_CMD" "${SAVEROOM_ARGS[@]}"
fi

if [[ "$MODE" != "apps" ]]; then
  start_audio
fi

rule

if [[ "$MODE" != "audio" && "$MODE" != "music" ]]; then
  sleep 2
  apply_layout
fi

if ((FAULTS == 0)); then
  printf '  %s%s✔ Environment ready.%s %sHave a good session, %s.%s\n\n' \
    "$B" "$GRN" "$R" "$GRY" "$SESSION_USER" "$R"
else
  printf '  %s%s✔ Environment ready, %d window(s) not placed.%s %sSee above for why.%s\n\n' \
    "$B" "$AMB" "$FAULTS" "$R" "$GRY" "$R"
fi

notify "Environment ready" "Antigravity · Brave · Ghostty · Claude"

if [[ -n "${ENVSTART_X11:-}" ]]; then
  read -r -p "press enter to close this console " _ || true
fi
