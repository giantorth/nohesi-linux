#!/bin/bash
# Installs nohesi-linux for the current user.
#
#   ./install.sh              copy into ~/.local (or PREFIX)
#   ./install.sh --link       link to this folder instead of copying (for development)
#   ./install.sh --desktop    also put the shortcuts on the desktop
#   ./install.sh --uninstall  remove what an install added
#
# Files: PREFIX/share/nohesi-linux/ (scripts and wv2shim.exe), the commands in
# PREFIX/bin, menu entries in PREFIX/share/applications and icons in
# PREFIX/share/icons/hicolor.
set -eu

SRC=$(dirname "$(readlink -f "$0")")
PREFIX=${PREFIX:-$HOME/.local}
LIBDIR=$PREFIX/share/nohesi-linux
BINDIR=$PREFIX/bin
APPDIR=$PREFIX/share/applications
ICONDIR=$PREFIX/share/icons/hicolor
DESKDIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")

COMMANDS="nohesi-launcher ac-content-manager"
FILES="$COMMANDS common.sh wv2shim.exe"

link=0 desktop=0 uninstall=0
for arg; do
    case $arg in
        --link) link=1 ;;
        --desktop) desktop=1 ;;
        --uninstall) uninstall=1 ;;
        -h|--help) sed -n '2,/^set /{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

if [ $uninstall = 1 ]; then
    for c in $COMMANDS; do
        if [ -L "$BINDIR/$c" ]; then
            rm -v "$BINDIR/$c"
        elif [ -e "$BINDIR/$c" ]; then
            echo "Not a link, left in place: $BINDIR/$c" >&2
        fi
        rm -fv "$APPDIR/$c.desktop" "$DESKDIR/$c.desktop"
        rm -fv "$ICONDIR"/*/apps/"$c".png
    done
    rm -rfv "$LIBDIR"
    exit 0
fi

case $BINDIR in
    *[\"\`\$\\]*) echo "PREFIX must not contain \" \` \$ or \\: $PREFIX" >&2; exit 1 ;;
esac

if [ ! -f "$SRC/wv2shim.exe" ]; then
    echo "wv2shim.exe is missing. Build it with 'make' (needs mingw-w64-gcc)," >&2
    echo "or install from a release tarball, which includes it." >&2
    exit 1
fi

# Commands
if [ $link = 1 ]; then
    rm -rf "$LIBDIR"
    target=$SRC
else
    mkdir -p "$LIBDIR"
    for f in $FILES; do
        install -m "$([ "$f" = common.sh ] && echo 644 || echo 755)" "$SRC/$f" "$LIBDIR/$f"
    done
    target=$LIBDIR
fi
mkdir -p "$BINDIR"
for c in $COMMANDS; do
    ln -sfn "$target/$c" "$BINDIR/$c"
done

# Icons. No Hesi's is the one Proton extracted when the launcher's installer
# made its shortcut; it is only there once the launcher is installed in the
# prefix. Content Manager's is content-manager.png, if this folder has one.
if [ -f "$SRC/content-manager.png" ]; then
    install -Dm 644 "$SRC/content-manager.png" "$ICONDIR/256x256/apps/ac-content-manager.png"
fi
nohesi_icon=$(
    # shellcheck source=common.sh
    . "$SRC/common.sh"
    find_game 2>/dev/null
    find "$PFX/drive_c/proton_shortcuts/icons" -path '*/apps/*_NoHesiLauncher.0.png' 2>/dev/null |
        sort -V | tail -1   # the largest size
) || true
if [ -n "$nohesi_icon" ]; then
    size=$(basename "$(dirname "$(dirname "$nohesi_icon")")")
    install -Dm 644 "$nohesi_icon" "$ICONDIR/$size/apps/nohesi-launcher.png"
else
    echo "No Hesi Launcher icon not found in the prefix; run this again after installing the launcher." >&2
fi

# Menu entries, with the full path in Exec because ~/.local/bin is not always
# in the PATH of the desktop session, and a generic icon if there is no own one.
mkdir -p "$APPDIR"
for c in $COMMANDS; do
    icon=$c
    compgen -G "$ICONDIR/*/apps/$c.png" >/dev/null || icon=applications-games
    sed -e "s|^Exec=.*|Exec=\"$BINDIR/$c\"|" -e "s|^Icon=.*|Icon=$icon|" \
        "$SRC/$c.desktop" > "$APPDIR/$c.desktop"
    chmod 644 "$APPDIR/$c.desktop"
    if [ $desktop = 1 ]; then
        mkdir -p "$DESKDIR"
        install -m 755 "$APPDIR/$c.desktop" "$DESKDIR/$c.desktop"
        # GNOME only starts desktop launchers that are marked as trusted.
        gio set "$DESKDIR/$c.desktop" metadata::trusted true 2>/dev/null || true
    fi
done

echo "Installed: $BINDIR/nohesi-launcher, $BINDIR/ac-content-manager"
case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *) echo "Note: $BINDIR is not in PATH. The menu entries work without it." ;;
esac
