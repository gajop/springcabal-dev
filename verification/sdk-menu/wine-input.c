#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static HWND window;
static BOOL CALLBACK find_window(HWND candidate, LPARAM unused)
{
    (void)unused;
    RECT size;
    if (IsWindowVisible(candidate) && GetClientRect(candidate, &size) &&
        size.right == 1280 && size.bottom == 720) {
        window = candidate;
        return FALSE;
    }
    return TRUE;
}

int main(int argc, char **argv)
{
    EnumWindows(find_window, 0);
    if (!window || !SetForegroundWindow(window)) {
        fprintf(stderr, "Cannot focus the test window: %lu\n", GetLastError());
        return 1;
    }
    Sleep(200);
    for (int i = 1; i < argc; ++i) {
        INPUT input = {0};
        input.type = INPUT_KEYBOARD;
        input.ki.wVk = (WORD)strtoul(argv[i], NULL, 0);
        input.ki.wScan = (WORD)MapVirtualKey(input.ki.wVk, MAPVK_VK_TO_VSC);
        input.ki.dwFlags = input.ki.wVk >= VK_LEFT && input.ki.wVk <= VK_DOWN ? KEYEVENTF_EXTENDEDKEY : 0;
        if (SendInput(1, &input, sizeof(input)) != 1) return 2;
        Sleep(100);
        input.ki.dwFlags |= KEYEVENTF_KEYUP;
        if (SendInput(1, &input, sizeof(input)) != 1) return 3;
        Sleep(100);
    }
    return 0;
}
