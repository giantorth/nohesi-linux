/*
 * Shim for msedgewebview2.exe, used only by the No Hesi Launcher under Proton.
 *
 * The launcher passes its own AdditionalBrowserArguments to WebView2, which
 * makes WebView2 ignore WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS and the registry
 * policy. WebView2's GPU process crash-loops under Wine unless extra Chromium
 * flags are given, so this shim sits in a WEBVIEW2_BROWSER_EXECUTABLE_FOLDER
 * and starts the real browser with NOHESI_WV2_ARGS appended.
 *
 * Build: make (needs mingw-w64-gcc).
 *
 *   NOHESI_WV2_REAL  full Windows path of the real msedgewebview2.exe
 *   NOHESI_WV2_ARGS  extra Chromium switches to append
 */
#include <windows.h>
#include <wchar.h>

static const wchar_t *skip_argv0(const wchar_t *p)
{
    if (*p == L'"') {
        p++;
        while (*p && *p != L'"') p++;
        if (*p) p++;
    } else {
        while (*p && *p != L' ' && *p != L'\t') p++;
    }
    return p;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, LPWSTR unused, int show)
{
    static wchar_t real[1024], extra[4096], cmd[32768];
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    DWORD code = 1;
    const wchar_t *rest = skip_argv0(GetCommandLineW());

    if (!GetEnvironmentVariableW(L"NOHESI_WV2_REAL", real, 1024))
        return 2;
    if (!GetEnvironmentVariableW(L"NOHESI_WV2_ARGS", extra, 4096))
        extra[0] = 0;

    _snwprintf(cmd, 32767, L"\"%ls\"%ls %ls", real, rest, extra);

    GetStartupInfoW(&si);
    if (!CreateProcessW(real, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi))
        return 3;
    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}
