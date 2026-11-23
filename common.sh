# shellcheck shell=bash
# Shared by nohesi-launcher and ac-content-manager. Sourced, not run. The
# variables set here are used by those scripts, hence SC2034 (unused) is off.
# shellcheck disable=SC2034

APPID=244210

die() { echo "${0##*/}: $*" >&2; exit 1; }
warn() { echo "${0##*/}: warning: $*" >&2; }

# Settings from ~/.config/nohesi-linux/config: one NAME=value per line, '#'
# starts a comment. Each value is exported, unless the variable is already set
# in the environment (so "MANGOHUD=0 nohesi-launcher" overrides the file).
load_config() {
    local file="${XDG_CONFIG_HOME:-$HOME/.config}/nohesi-linux/config" key value
    [ -f "$file" ] || return 0
    while IFS='=' read -r key value || [ -n "$key" ]; do
        [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        [[ $value =~ ^\"(.*)\"$ || $value =~ ^\'(.*)\'$ ]] && value=${BASH_REMATCH[1]}
        [ -n "${!key+set}" ] || export "$key=$value"
    done < "$file"
}

# Sets STEAM (Steam client folder), COMPAT and PFX (Assetto Corsa's Proton
# prefix) and GAME (Assetto Corsa folder). The game, and with it the prefix, can
# be in any Steam library, so they are looked up in libraryfolders.vdf.
find_game() {
    local d lib
    if [ -n "${STEAM_DIR:-}" ]; then
        STEAM=$STEAM_DIR
    else
        # ~/.steam/root links to the client folder for every native install,
        # including Debian's ~/.steam/debian-installation.
        for d in "$HOME/.steam/root" "$HOME/.steam/steam" "$HOME/.local/share/Steam"; do
            [ -d "$d/steamapps" ] && { STEAM=$(readlink -f "$d"); break; }
        done
    fi
    [ -d "$STEAM/steamapps" ] || die "Steam not found. Set STEAM_DIR to the Steam folder."

    lib=$(awk -F'"' -v id="$APPID" '$2 == "path" {p = $4} $2 == id {print p; exit}' \
        "$STEAM/steamapps/libraryfolders.vdf" 2>/dev/null)
    [ -d "$lib/steamapps" ] || lib=$STEAM

    COMPAT="$lib/steamapps/compatdata/$APPID"
    [ -d "$COMPAT/pfx" ] || COMPAT="$STEAM/steamapps/compatdata/$APPID"
    [ -d "$COMPAT/pfx" ] || die "Assetto Corsa's Proton prefix not found. Start Assetto Corsa from Steam once."
    PFX="$COMPAT/pfx"
    GAME="$lib/steamapps/common/assettocorsa"

    # The steamapps folder of every library except the Steam folder,
    # colon-separated, for STEAM_COMPAT_LIBRARY_PATHS.
    LIBS=
    while IFS= read -r d; do
        [ "$(readlink -f "$d")" = "$(readlink -f "$STEAM")" ] || LIBS+="${LIBS:+:}$d/steamapps"
    done < <(awk -F'"' '$2 == "path" {print $4}' "$STEAM/steamapps/libraryfolders.vdf" 2>/dev/null)
}

# Sets TOOL and PROTON to the Proton build that last ran the prefix, so every
# program in the prefix shares one wineserver. Line 2 of config_info is that
# build's font folder. GE-Proton up to 11-3 also wrote its name to the version
# file; from 11-12 on that file holds a version number instead.
find_proton() {
    TOOL=$(sed -n '2s|/files/share/fonts/$||p' "$COMPAT/config_info" 2>/dev/null)
    [ -x "$TOOL/proton" ] || TOOL="$STEAM/compatibilitytools.d/$(cat "$COMPAT/version" 2>/dev/null)"
    PROTON="$TOOL/proton"
    [ -x "$PROTON" ] || die "Proton not found at: $PROTON. Start Assetto Corsa from Steam once with GE-Proton selected."
}

# Environment for "proton run" outside of Steam.
proton_env() {
    # The DOTNET_* variables are set system-wide by the Linux .NET SDK (for
    # example /etc/profile.d/dotnet.sh). The No Hesi Launcher is a Windows .NET
    # single-file app and inherits them: DOTNET_BUNDLE_EXTRACT_BASE_DIR then
    # points at a Linux path it cannot extract to, and the launcher exits with
    # code 1 before it shows a window.
    unset DOTNET_BUNDLE_EXTRACT_BASE_DIR DOTNET_ROOT DOTNET_TOOLS_PATH

    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM"
    # Proton's steam.exe rewrites C:\Program Files (x86)\Steam\steamapps\
    # libraryfolders.vdf on each start: the Steam folder, then the parent of
    # each steamapps folder in STEAM_COMPAT_LIBRARY_PATHS. Without that list the
    # No Hesi Launcher does not find Assetto Corsa in another library.
    [ -z "$LIBS" ] || export STEAM_COMPAT_LIBRARY_PATHS="$LIBS"
    export STEAM_COMPAT_DATA_PATH="$COMPAT"
    export SteamAppId="$APPID" SteamGameId="$APPID" STEAM_COMPAT_APP_ID="$APPID"

    # Custom Shaders Patch is dwrite.dll in the Assetto Corsa folder. Wine only
    # loads it for acs.exe with this override; without it servers reject the
    # join with "server is running a different protocol".
    export WINEDLLOVERRIDES="dwrite=n,b${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
}

# The launcher and Content Manager start acs.exe themselves, so Steam launch
# options (gamemoderun etc.) never apply. While acs.exe runs, this keeps the
# screen on and puts the game in GameMode. Only acs.exe is covered: an idle
# launcher does not keep the system awake. Sets WATCH to the watcher's PID.
# Each step is logged to stderr (the journal, when started from the menu), so a
# session without GameMode or with the screens sleeping can be traced.
watch_acs() {
    (
        echo "watch: started (pid $BASHPID)" >&2
        while sleep 5; do
            # Match the Windows path in the command line, not the process name:
            # CSP renames AC's main thread to "AC: main thread" seconds after
            # start, which also renames the process, so "pgrep -x acs.exe"
            # misses it after that.
            pid=$(pgrep -u "$UID" -f '^[A-Za-z]:\\.*\\acs\.exe( |$)' | head -1)
            [ -n "$pid" ] || continue
            echo "watch: acs.exe pid $pid found" >&2
            if command -v gamemoded >/dev/null; then
                echo "watch: gamemoded: $(gamemoded -r"$pid" 2>&1 | tr '\n' ' ')" >&2
            fi
            if command -v kde-inhibit >/dev/null; then
                kde-inhibit --power --screenSaver tail --pid="$pid" -f /dev/null
            elif command -v systemd-inhibit >/dev/null; then
                systemd-inhibit --what=idle:sleep --who="${0##*/}" \
                    --why="Assetto Corsa is running" tail --pid="$pid" -f /dev/null
            fi
            echo "watch: inhibit for pid $pid ended (rc $?)" >&2
            # If the inhibitor failed to start, wait here instead of
            # registering the same game again every 5 seconds.
            tail --pid="$pid" -f /dev/null
        done
    ) &
    WATCH=$!
}

# Runs a Windows program with Proton and the acs.exe watcher, and exits with
# its exit code.
run_with_watch() {
    local status
    watch_acs
    "$PROTON" run "$@"
    status=$?
    kill "$WATCH" 2>/dev/null
    exit $status
}
