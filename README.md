# nohesi-linux

Runs the No Hesi Launcher for Assetto Corsa on Linux, inside the game's Proton
prefix (Steam app 244210). Also starts Content Manager in the same prefix, so
both can run at the same time.

## Requirements

- Steam, native install. The scripts find it through `~/.steam/root` or
  `~/.local/share/Steam`, or `STEAM_DIR` if set. Assetto Corsa can be in any
  Steam library. Flatpak Steam is not tested.
- GE-Proton11-12 or newer, set as Assetto Corsa's compatibility tool in Steam.
  The scripts use the Proton build that last ran the prefix, so start Assetto
  Corsa from Steam once after you change it. GE-Proton11-12 shares cursors
  across processes; older builds show no cursor, or a stale one, over the
  launcher's web content.
- `wintrust.dll` built with `wintrust-implement-cryptsipverifyindirectdata.patch`
  (submitted to GE-Proton as
  [#972](https://github.com/GloriousEggroll/proton-ge-custom/pull/972)). Custom
  Shaders Patch checks its signed `dwrite.dll` with
  `CryptSIPVerifyIndirectData`, which is a stub in Wine. Without the fix,
  No Hesi shows you as "playing offline", the agreement prompt returns on every
  start, and CSP Setup Exchange fails. The launcher warns when the fix is
  missing. See [The wintrust fix](#the-wintrust-fix).
- `protontricks`, for the one-time prefix setup.
- Optional: GameMode (`gamemoded`), and `kde-inhibit` (KDE) or `systemd-inhibit`
  to keep the screen on while the game runs.

## Install

### 1. Prepare the prefix (once)

Start Assetto Corsa from Steam once with GE-Proton, so the prefix exists. Then:

```bash
# Launcher (keep the default install path)
protontricks-launch --no-bwrap --appid 244210 NoHesiLauncher-Setup.exe

# Windows 10 mode for WebView2, Windows 11 for the launcher (the prefix is Windows 7)
protontricks --no-bwrap -c '
  for e in MicrosoftEdgeUpdate.exe MicrosoftEdgeUpdateSetup.exe \
           MicrosoftEdgeWebView2RuntimeInstallerX64.exe setup.exe \
           msedgewebview2.exe; do
    wine reg add "HKCU\\Software\\Wine\\AppDefaults\\$e" /v Version /d win10 /f
  done
  wine reg add "HKCU\\Software\\Wine\\AppDefaults\\NoHesiLauncher.exe" /v Version /d win11 /f' 244210

# WebView2 Evergreen Standalone runtime (x64), from Microsoft
curl -Lo MicrosoftEdgeWebView2RuntimeInstallerX64.exe \
  'https://go.microsoft.com/fwlink/?linkid=2124701'
protontricks --no-bwrap -c \
  'wine MicrosoftEdgeWebView2RuntimeInstallerX64.exe /silent /install' 244210
```

The No Hesi Launcher draws its window with WebView2, so it needs the Windows
WebView2 runtime inside the prefix. The `curl` line downloads Microsoft's
Evergreen Standalone x64 installer. It is also on the
[WebView2 download page](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)
under "Evergreen Standalone Installer", x64. `ac-content-manager` does not need it.

### 2. Install nohesi-linux

Download `nohesi-linux-VERSION.tar.gz` and its `.sha256` file from the
Releases page, then:

```bash
sha256sum -c nohesi-linux-VERSION.tar.gz.sha256
tar xzf nohesi-linux-VERSION.tar.gz
cd nohesi-linux-VERSION
./install.sh --desktop
```

This installs into `~/.local`: the scripts in `~/.local/share/nohesi-linux`,
the commands `nohesi-launcher` and `ac-content-manager` in `~/.local/bin`, and
menu entries. `--desktop` also puts the shortcuts on the desktop. Set
`PREFIX` to install somewhere else. The No Hesi icon comes from the launcher
installed in step 1; if you install nohesi-linux first, run `./install.sh`
again afterwards to get it. For a Content Manager icon, put a 256x256
`content-manager.png` next to `install.sh` before you run it.

To uninstall: `./install.sh --uninstall`.

### The wintrust fix

Until GE-Proton includes the fix: build
`dlls/wintrust/x86_64-windows/wintrust.dll` from the same GE-Proton Wine
source with `wintrust-implement-cryptsipverifyindirectdata.patch` applied, and
replace `files/lib/wine/x86_64-windows/wintrust.dll` in the Proton tool with it.
Assetto Corsa is 64-bit, so the 32-bit DLL is not needed. Each new GE-Proton
version installs to a new folder with the stock DLL, so do this again after an
update.

## Usage

Start "No Hesi Launcher" from the application menu, or run `nohesi-launcher`.
Steam must be running. Starting `NoHesiLauncher.exe` any other way gives a
black window.

Content Manager: start "AC Content Manager", or run `ac-content-manager`. It
starts Content Manager in the same prefix with the same Proton build, so it
also works while the No Hesi Launcher runs.

## Settings

`~/.config/nohesi-linux/config` sets environment variables for both commands,
one `NAME=value` per line (`#` starts a comment line). A variable that is
already set in the environment overrides the file. For example:

```bash
# MangoHud overlay on the game
MANGOHUD=1
```

`MANGOHUD=1` also reaches the launcher, Content Manager and their browser
processes. To show the overlay on `acs.exe` only, create these files in
`~/.config/MangoHud/`, each with the line `no_display`:
`wine-NoHesiLauncher.conf`, `wine-msedgewebview2.conf`,
`wine-AssettoCorsa.conf`, `wine-CefSharp.BrowserSubprocess.conf`.

Other variables: `STEAM_DIR` (Steam folder), `NOHESI_WV2_ARGS` (see
[Debugging](#debugging)), and anything Proton reads, such as `PROTON_LOG=1`.

## What the scripts do

- Find Steam, the library that has Assetto Corsa (`libraryfolders.vdf`), its
  prefix, and the Proton build that last ran the prefix (from the prefix's
  `config_info`). The launcher warns if that build's `wintrust.dll` lacks the
  fix.
- Pass every Steam library to Proton in `STEAM_COMPAT_LIBRARY_PATHS`. Proton
  writes the prefix's `C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf`
  from it on each start, and the No Hesi Launcher looks for Assetto Corsa
  there. Without it the file lists only the Steam folder.
- Unset `DOTNET_BUNDLE_EXTRACT_BASE_DIR`, `DOTNET_ROOT` and `DOTNET_TOOLS_PATH`.
  The Linux .NET SDK sets them and the launcher exits with code 1 if it
  inherits them.
- Start WebView2 with
  `--disable-features=IsolateOrigins,site-per-process,ForceSWDCompWhenDCompFallbackRequired`.
  Without it the WebView2 GPU process calls `DCompositionCreateDevice`, which
  Wine does not implement, and the window goes black.
- Pass that switch through `wv2shim.exe`. WebView2 ignores
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` for this launcher, so the script
  mirrors the WebView2 runtime folder to `C:\nohesi-wv2`, puts the shim there
  as `msedgewebview2.exe`, and sets `WEBVIEW2_BROWSER_EXECUTABLE_FOLDER`.
- Start the launcher with `proton run` and Assetto Corsa's app ID, so Proton's
  `steam.exe` bridge runs in the prefix and the launcher sees Steam as running.
- Write the signed-in Steam account from `loginusers.vdf` to the registry
  values the launcher reads (`ActiveProcess\ActiveUser`, `LastGameNameUsed`).
  Proton's `steam.exe` does not set them.
- Set `WINEDLLOVERRIDES=dwrite=n,b` so the game loads Custom Shaders Patch.
- While `acs.exe` runs, hold a screen and power inhibit (`kde-inhibit`, else
  `systemd-inhibit`) and request GameMode for it (`gamemoded -r`). The launcher
  starts the game itself, so Steam launch options do not apply. An idle
  launcher does not inhibit anything.

## Debugging

`NOHESI_WV2_ARGS` overrides the browser switches. Add
`--enable-logging --log-file=C:\nh-chrome.log` to it and read the `FATAL` and
`ERROR` lines.

For "playing offline", run with `WINEDEBUG=+wintrust` and look for
`CryptSIPVerifyIndirectData` in the game's output: `returning 1` is correct,
`stub` means the fix is missing.

Started from the KDE menu, the scripts log to the journal:
`journalctl --user -t nohesi-launcher` (or `-t ac-content-manager`).

## Building from source

Needs `make` and `mingw-w64-gcc` (Arch), `gcc-mingw-w64-x86-64` (Debian,
Ubuntu) or `mingw64-gcc` (Fedora).

```bash
make                    # builds wv2shim.exe from wv2shim.c
./install.sh --link     # installs links to this folder, so edits apply at once
make check              # shellcheck and desktop-file-validate
make dist               # nohesi-linux-VERSION.tar.gz, as in a release
```

`wv2shim.exe` is not in the repository. Releases build it from `wv2shim.c`,
and the build is reproducible: the same source and compiler give the same file.

## Releases

`.github/workflows/build.yml` runs `make check` and `make dist` on every push
and pull request. Each push to `main` publishes the tarball as a prerelease
tagged `snapshot-VERSION`, for example `snapshot-1.0-3-gabc1234` (three commits
after v1.0). To publish a full release, push a tag:

```bash
git tag v1.0
git push origin v1.0
```

The workflow then creates the release `v1.0` with `nohesi-linux-1.0.tar.gz` and
its `.sha256` file. Prereleases never become the "Latest" release, so the
Releases page keeps pointing users at the last tagged version.
