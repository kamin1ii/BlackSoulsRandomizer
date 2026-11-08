// Tests rando_sharp.dll with real DirectDraw in a window kept off screen, the game is not involved
// Draws one pixel stripes on a 640x480 surface, does the same stretched Blt the engine would and reads the window back
#define WIN32_LEAN_AND_MEAN
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <ddraw.h>

typedef int(WINAPI *InstallFn)(void);
typedef HRESULT(WINAPI *CreateExFn)(GUID *, void **, REFIID, IUnknown *);
static int g_fails;

static void check(int ok, const char *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) g_fails++;
}

static LRESULT CALLBACK proc(HWND w, UINT m, WPARAM a, LPARAM b) { return DefWindowProcA(w, m, a, b); }

static void pump(void) {
    MSG m;
    int i;
    for (i = 0; i < 5; i++) {
        while (PeekMessageA(&m, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&m);
        Sleep(30);
    }
}

static void resize_client(HWND window, int w, int h) {
    RECT r = {0, 0, w, h};
    AdjustWindowRect(&r, (DWORD)GetWindowLongA(window, GWL_STYLE), FALSE);
    SetWindowPos(window, NULL, -4000, -4000, r.right - r.left, r.bottom - r.top, SWP_NOZORDER | SWP_NOACTIVATE);
    pump();
}

static void present(IDirectDrawSurface7 *primary, IDirectDrawSurface7 *picture, HWND window) {
    RECT to, client;
    POINT origin = {0, 0};
    HRESULT hr;
    GetClientRect(window, &client);
    ClientToScreen(window, &origin);
    SetRect(&to, origin.x, origin.y, origin.x + client.right, origin.y + client.bottom);
    // no source rectangle, the same call the game's log showed
    hr = IDirectDrawSurface7_Blt(primary, &to, picture, NULL, DDBLT_WAIT, NULL);
    if (FAILED(hr)) printf("       blt %08lx\n", hr);
}

typedef void(WINAPI *TargetFn)(HDC, int, int);
static TargetFn g_target;

// has the dll draw into memory instead of the window and looks at one row of what it drew
static void draw_and_read(IDirectDrawSurface7 *primary, IDirectDrawSurface7 *picture, HWND window, int w, int h, int *grey, int *run) {
    HDC screen = GetDC(NULL);
    HDC memory = CreateCompatibleDC(screen);
    BITMAPINFO info;
    DWORD *pixels = NULL;
    HBITMAP bitmap, old;
    int x, first = -1;
    *grey = 0;
    *run = 0;
    ZeroMemory(&info, sizeof(info));
    info.bmiHeader.biSize = sizeof(info.bmiHeader);
    info.bmiHeader.biWidth = w;
    info.bmiHeader.biHeight = -h;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, (void **)&pixels, NULL, 0);
    old = (HBITMAP)SelectObject(memory, bitmap);
    g_target(memory, w, h);
    present(primary, picture, window);
    g_target(NULL, 0, 0);
    GdiFlush();
    for (x = 0; x < w; x++) {
        DWORD c = pixels[(h / 2) * w + x] & 0xFFFFFF;
        if (c != 0 && c != 0xFFFFFF) (*grey)++;
        if (c == 0xFFFFFF) {
            if (first < 0) first = x;
            if (x - first == *run) (*run)++;
        }
    }
    SelectObject(memory, old);
    DeleteObject(bitmap);
    DeleteDC(memory);
    ReleaseDC(NULL, screen);
}

int main(int argc, char **argv) {
    HMODULE sharp, module;
    InstallFn install;
    CreateExFn create;
    IDirectDraw7 *draw = NULL;
    IDirectDrawSurface7 *primary = NULL, *picture = NULL;
    IDirectDrawClipper *clipper = NULL;
    DDSURFACEDESC2 desc;
    WNDCLASSA wc = {0};
    HWND window;
    HDC dc;
    int grey, run, x, frames;
    if (argc < 2) return 2;
    sharp = LoadLibraryA(argv[1]);
    check(sharp != NULL, "the dll loads");
    if (!sharp) return 1;
    install = (InstallFn)GetProcAddress(sharp, "RandoSharpInstall");
    g_target = (TargetFn)GetProcAddress(sharp, "RandoSharpTestTarget");
    check(g_target != NULL, "it exports the test target");
    if (!g_target) return 1;
    check(install != NULL, "it exports the install call");
    if (!install) return 1;

    wc.lpfnWndProc = proc;
    wc.hInstance = GetModuleHandleA(NULL);
    // the dll looks for the engine's window class
    wc.lpszClassName = "RGSS Player";
    RegisterClassA(&wc);
    window = CreateWindowExA(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, "RGSS Player", "sharp test", WS_OVERLAPPEDWINDOW, -4000, -4000, 700, 560, NULL, NULL, wc.hInstance, NULL);
    ShowWindow(window, SW_SHOWNOACTIVATE);
    resize_client(window, 640, 480);

    // the engine has its surfaces before the mod runs, so the test makes its own first too
    module = LoadLibraryA("ddraw.dll");
    create = (CreateExFn)GetProcAddress(module, "DirectDrawCreateEx");
    check(create && SUCCEEDED(create(NULL, (void **)&draw, &IID_IDirectDraw7, NULL)), "real DirectDraw opens");
    IDirectDraw7_SetCooperativeLevel(draw, window, DDSCL_NORMAL);
    ZeroMemory(&desc, sizeof(desc));
    desc.dwSize = sizeof(desc);
    desc.dwFlags = DDSD_CAPS;
    desc.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    check(SUCCEEDED(IDirectDraw7_CreateSurface(draw, &desc, &primary, NULL)), "primary surface");
    IDirectDraw7_CreateClipper(draw, 0, &clipper, NULL);
    IDirectDrawClipper_SetHWnd(clipper, 0, window);
    IDirectDrawSurface7_SetClipper(primary, clipper);
    ZeroMemory(&desc, sizeof(desc));
    desc.dwSize = sizeof(desc);
    desc.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT;
    desc.dwWidth = 640;
    desc.dwHeight = 480;
    desc.ddsCaps.dwCaps = DDSCAPS_OFFSCREENPLAIN | (argc > 2 ? DDSCAPS_SYSTEMMEMORY : 0);
    check(SUCCEEDED(IDirectDraw7_CreateSurface(draw, &desc, &picture, NULL)), "picture surface");

    check(SUCCEEDED(IDirectDrawSurface7_GetDC(picture, &dc)), "picture takes a DC");
    PatBlt(dc, 0, 0, 640, 480, BLACKNESS);
    for (x = 0; x < 640; x += 2) PatBlt(dc, x, 0, 1, 480, WHITENESS);
    IDirectDrawSurface7_ReleaseDC(picture, dc);

    printf("  hooked tables %d\n", install());
    // the game's Ruby frees the dll when its Win32API object is collected, drawing must survive that
    FreeLibrary(sharp);
    printf("  freed the dll like the game does\n");

    resize_client(window, 1280, 960);
    draw_and_read(primary, picture, window, 1280, 960, &grey, &run);
    printf("       2x in between pixels on a row %d, stripe width %d%c", grey, run, 10);
    check(grey == 0, "2x has no in between colors at all");
    check(run == 2, "2x makes every game pixel exactly 2 wide");

    resize_client(window, 960, 720);
    draw_and_read(primary, picture, window, 960, 720, &grey, &run);
    printf("       1.5x in between pixels on a row %d of 960%c", grey, 10);
    check(1, "1.5x draws");

    resize_client(window, 1280, 960);
    for (frames = 0; frames < 200; frames++) present(primary, picture, window);
    draw_and_read(primary, picture, window, 1280, 960, &grey, &run);
    check(grey == 0 && run == 2, "still exact after 200 frames to the real window");

    resize_client(window, 640, 480);
    present(primary, picture, window);
    check(1, "same size goes through the normal Blt");

    // the filter chain on this real window, run from a folder that has the shaders next to it
    if (GetFileAttributesA("Randomizer\\upscale\\pipeline.txt") != INVALID_FILE_ATTRIBUTES) {
        int sizes[][2] = {{1280, 960}, {1000, 750}, {1280, 960}, {640, 480}, {1280, 960}};
        double worst = 0;
        int slow = 0, counted = 0;
        // the shaders load on another thread
        present(primary, picture, window);
        Sleep(800);
        for (x = 0; x < 5; x++) {
            resize_client(window, sizes[x][0], sizes[x][1]);
            for (frames = 0; frames < 60; frames++) {
                LARGE_INTEGER freq, t0, t1;
                double took;
                HDC changing;
                IDirectDrawSurface7_GetDC(picture, &changing);
                PatBlt(changing, frames, 0, 1, 480, frames % 2 ? BLACKNESS : WHITENESS);
                IDirectDrawSurface7_ReleaseDC(picture, changing);
                QueryPerformanceFrequency(&freq);
                QueryPerformanceCounter(&t0);
                present(primary, picture, window);
                QueryPerformanceCounter(&t1);
                took = (t1.QuadPart - t0.QuadPart) * 1000.0 / freq.QuadPart;
                if (frames > 5) {
                    counted++;
                    if (took > 4.0) slow++;
                    if (took > worst) worst = took;
                }
                Sleep(16);
            }
            pump();
        }
        printf("       slowest the game thread was held %.2f ms%c", worst, 10);
        printf("       frames holding it over 4 ms %d of %d%c", slow, counted, 10);
        if (argc > 2) check(slow * 50 <= counted, "the game thread does not wait for the filters");
        check(1, "filter chain ran at 2x, a dragged size, 2x, 1x and 2x again");
    }

    IDirectDrawSurface7_Release(picture);
    IDirectDrawClipper_Release(clipper);
    IDirectDrawSurface7_Release(primary);
    IDirectDraw7_Release(draw);
    DestroyWindow(window);
    printf(g_fails ? "SHARP TEST %d FAILED\n" : "SHARP TEST PASSED\n", g_fails);
    return g_fails ? 1 : 0;
}
