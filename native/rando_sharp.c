// Loaded by the mod inside the game. The engine draws with DirectDraw and its stretched Blt to the window is the blur
// This catches that one Blt and draws the same picture with exact pixels instead
// Anything unexpected falls back to the original Blt so the game keeps working
#define WIN32_LEAN_AND_MEAN
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <ddraw.h>
#include "upscale_engine.h"

#define BLT_SLOT 5
#define BLTFAST_SLOT 7
#define FLIP_SLOT 11
#define LOG_LIMIT 300
#define VERSIONS 5

typedef HRESULT(WINAPI *BltFn)(void *, LPRECT, void *, LPRECT, DWORD, LPDDBLTFX);
typedef HRESULT(WINAPI *BltFastFn)(void *, DWORD, DWORD, void *, LPRECT, DWORD);
typedef HRESULT(WINAPI *FlipFn)(void *, void *, DWORD);
typedef HRESULT(WINAPI *CreateExFn)(GUID *, void **, REFIID, IUnknown *);
typedef HRESULT(WINAPI *GetDCFn)(void *, HDC *);
typedef HRESULT(WINAPI *ReleaseDCFn)(void *, HDC);
typedef HRESULT(WINAPI *GetCapsFn)(void *, void *);
typedef HRESULT(WINAPI *GetDescFn)(void *, void *);
typedef HRESULT(WINAPI *LockFn)(void *, LPRECT, void *, DWORD, HANDLE);
typedef HRESULT(WINAPI *UnlockFn)(void *, LPVOID);

// every surface interface version has its own table, Blt, GetCaps, GetDC and ReleaseDC sit at the same slots in all of them
#define GETCAPS_SLOT 14
#define GETDC_SLOT 17
#define RELEASEDC_SLOT 26
#define LOCK_SLOT 25
#define UNLOCK_SLOT 32
#define GETDESC_SLOT 22

typedef struct {
    void **table;
    BltFn blt;
    BltFastFn fast;
    FlipFn flip;
    long blt_calls, fast_calls, flip_calls;
} Hooked;

static Hooked g_hooks[VERSIONS];
static int g_count, g_installed, g_inside;
static volatile LONG g_log_lines;
static long g_sharp_frames, g_fallbacks;
static int g_last_w, g_last_h;
static HDC g_mid_dc;
static HBITMAP g_mid_bitmap, g_mid_old;
static int g_mid_w, g_mid_h;
static HDC g_test_dc;
static int g_test_w, g_test_h;
static Upscale g_up;
static volatile int g_up_state;
static int g_thread_started;
static HDC g_frame_dc;
static HBITMAP g_frame_bitmap;
static BYTE *g_frame_pixels, *g_mail, *g_work, *g_last;
static CRITICAL_SECTION g_mail_lock;
static HANDLE g_mail_event, g_detached_event;
static HWND g_mail_window;
static UINT g_mail_w, g_mail_h;
static int g_mail_detach;
static volatile long g_blts;
static long g_blts_before, g_grabs;
static double g_grab_ms, g_grab_peak;
static int g_grab_noted;
#define FRAME_W 640
#define FRAME_H 480
#define FRAME_BYTES (FRAME_W * FRAME_H * 4)

static void note(const char *format, ...) {
    FILE *f;
    va_list args;
    if (InterlockedIncrement(&g_log_lines) > LOG_LIMIT) return;
    f = fopen("Randomizer\\sharp_log.txt", g_log_lines == 1 ? "w" : "a");
    if (!f) return;
    va_start(args, format);
    vfprintf(f, format, args);
    va_end(args);
    fputc('\n', f);
    fclose(f);
}

static Hooked *find_hook(void *surface) {
    void **table = *(void ***)surface;
    int i;
    for (i = 0; i < g_count; i++)
        if (g_hooks[i].table == table) return &g_hooks[i];
    return NULL;
}

static void *patch_slot(void **table, int slot, void *replacement) {
    void *previous = table[slot];
    DWORD old;
    VirtualProtect(&table[slot], sizeof(void *), PAGE_EXECUTE_READWRITE, &old);
    table[slot] = replacement;
    VirtualProtect(&table[slot], sizeof(void *), old, &old);
    return previous;
}

static BOOL is_primary(void *surface) {
    DDSCAPS caps;
    GetCapsFn get_caps = (GetCapsFn)(*(void ***)surface)[GETCAPS_SLOT];
    // the caps block grew over versions, the first dword holds the flags in all of them
    DDSCAPS2 big;
    ZeroMemory(&big, sizeof(big));
    (void)caps;
    if (FAILED(get_caps(surface, &big))) return FALSE;
    return (big.dwCaps & DDSCAPS_PRIMARYSURFACE) != 0;
}

static HWND game_window(void) {
    static HWND window;
    if (!window || !IsWindow(window)) window = FindWindowA("RGSS Player", NULL);
    return window;
}

// the engine passes no source rectangle, which means the whole surface
// the description block has two sizes depending on the interface version
static BOOL surface_rect(void *surface, RECT *out) {
    GetDescFn get_desc = (GetDescFn)(*(void ***)surface)[GETDESC_SLOT];
    DDSURFACEDESC2 big;
    DDSURFACEDESC old_desc;
    ZeroMemory(&big, sizeof(big));
    big.dwSize = sizeof(big);
    if (SUCCEEDED(get_desc(surface, &big))) {
        SetRect(out, 0, 0, (int)big.dwWidth, (int)big.dwHeight);
        return TRUE;
    }
    ZeroMemory(&old_desc, sizeof(old_desc));
    old_desc.dwSize = sizeof(old_desc);
    if (SUCCEEDED(get_desc(surface, &old_desc))) {
        SetRect(out, 0, 0, (int)old_desc.dwWidth, (int)old_desc.dwHeight);
        return TRUE;
    }
    return FALSE;
}

static BOOL ensure_middle(HDC like, int w, int h) {
    if (g_mid_dc && g_mid_w == w && g_mid_h == h) return TRUE;
    if (g_mid_dc) {
        SelectObject(g_mid_dc, g_mid_old);
        DeleteObject(g_mid_bitmap);
        DeleteDC(g_mid_dc);
        g_mid_dc = NULL;
    }
    g_mid_dc = CreateCompatibleDC(like);
    if (!g_mid_dc) return FALSE;
    g_mid_bitmap = CreateCompatibleBitmap(like, w, h);
    if (!g_mid_bitmap) {
        DeleteDC(g_mid_dc);
        g_mid_dc = NULL;
        return FALSE;
    }
    g_mid_old = (HBITMAP)SelectObject(g_mid_dc, g_mid_bitmap);
    g_mid_w = w;
    g_mid_h = h;
    return TRUE;
}

static double now_ms(void) {
    static LARGE_INTEGER freq;
    LARGE_INTEGER t;
    if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t);
    return t.QuadPart * 1000.0 / freq.QuadPart;
}

// the filters run on their own thread so the game never waits for them, only the newest frame is ever drawn
static DWORD WINAPI filter_thread(LPVOID unused) {
    double spent = 0, peak = 0, started;
    long done = 0, skipped = 0;
    double window_start = now_ms();
    IDXGIDevice1 *dxgi = NULL;
    (void)unused;
    if (!up_create(&g_up, "Randomizer\\upscale")) {
        note("upscale off, %s", g_up.error);
        g_up_state = -1;
        return 0;
    }
    // one queued frame at most, more would add input lag
    if (SUCCEEDED(ID3D11Device_QueryInterface(g_up.device, &IID_IDXGIDevice1, (void **)&dxgi))) {
        IDXGIDevice1_SetMaximumFrameLatency(dxgi, 1);
        IDXGIDevice1_Release(dxgi);
    }
    g_up_state = 1;
    note("upscale ready, %d passes on its own thread", g_up.pass_count);
    for (;;) {
        HWND window;
        UINT w, h;
        BOOL detach, resized;
        WaitForSingleObject(g_mail_event, INFINITE);
        EnterCriticalSection(&g_mail_lock);
        memcpy(g_work, g_mail, FRAME_BYTES);
        window = g_mail_window;
        w = g_mail_w;
        h = g_mail_h;
        detach = g_mail_detach;
        g_mail_detach = 0;
        LeaveCriticalSection(&g_mail_lock);
        if (detach) {
            if (g_up.swap) {
                up_detach_window(&g_up);
                note("fullscreen, window picture released");
            }
            SetEvent(g_detached_event);
            continue;
        }
        if (!window || !w || !h) continue;
        started = now_ms();
        resized = g_up.swap_w != w || g_up.swap_h != h;
        if (!up_attach_window(&g_up, window, w, h)) {
            note("upscale off, %s", g_up.error);
            g_up_state = -1;
            return 0;
        }
        if (!resized && memcmp(g_work, g_last, FRAME_BYTES) == 0) {
            skipped++;
        } else {
            BOOL ok;
            memcpy(g_last, g_work, FRAME_BYTES);
            if (w == FRAME_W && h == FRAME_H) {
                // the window is at its normal size again, only the plain picture is needed
                ID3D11DeviceContext_UpdateSubresource(g_up.context, (ID3D11Resource *)g_up.texture[0], 0, NULL, g_work, FRAME_W * 4, 0);
                ok = up_present(&g_up, 0);
            } else {
                up_run(&g_up, g_work, FRAME_W * 4);
                ok = up_present(&g_up, g_up.final_index);
            }
            if (!ok) {
                note("upscale off, %s", g_up.error);
                g_up_state = -1;
                up_detach_window(&g_up);
                return 0;
            }
            done++;
            spent += now_ms() - started;
            if (now_ms() - started > peak) peak = now_ms() - started;
            if (resized) note("upscaling, window %ux%u", w, h);
        }
        if (now_ms() - window_start > 5000) {
            double seconds = (now_ms() - window_start) / 1000.0;
            long shown = g_blts;
            note("timing %.0f s, game %.1f fps, filter %.1f fps, same frames skipped %ld, filter %.1f ms peak %.1f ms, grab %.2f ms peak %.2f ms, window %ux%u",
                 seconds, (shown - g_blts_before) / seconds, done / seconds, skipped, done ? spent / done : 0.0, peak,
                 g_grabs ? g_grab_ms / g_grabs : 0.0, g_grab_peak, w, h);
            g_blts_before = shown;
            g_grabs = 0;
            g_grab_ms = 0;
            g_grab_peak = 0;
            done = skipped = 0;
            spent = peak = 0;
            window_start = now_ms();
        }
    }
}

// reading the surface memory is far cheaper than going through a GDI copy
static BOOL grab_by_lock(void *source, const RECT *rect) {
    void **table = *(void ***)source;
    LockFn lock = (LockFn)table[LOCK_SLOT];
    UnlockFn unlock = (UnlockFn)table[UNLOCK_SLOT];
    DDSURFACEDESC2 desc;
    int y;
    BOOL ok = FALSE;
    ZeroMemory(&desc, sizeof(desc));
    desc.dwSize = sizeof(DDSURFACEDESC2);
    if (FAILED(lock(source, NULL, &desc, DDLOCK_WAIT | DDLOCK_READONLY | DDLOCK_SURFACEMEMORYPTR, NULL))) {
        ZeroMemory(&desc, sizeof(desc));
        // the older description block is the same up to the fields read here
        desc.dwSize = sizeof(DDSURFACEDESC);
        if (FAILED(lock(source, NULL, &desc, DDLOCK_WAIT | DDLOCK_READONLY | DDLOCK_SURFACEMEMORYPTR, NULL))) return FALSE;
    }
    if (desc.lpSurface && desc.ddpfPixelFormat.dwRGBBitCount == 32 && desc.ddpfPixelFormat.dwRBitMask == 0xFF0000 && desc.ddpfPixelFormat.dwBBitMask == 0xFF) {
        for (y = 0; y < FRAME_H; y++) {
            memcpy(g_frame_pixels + (size_t)y * FRAME_W * 4,
                   (const BYTE *)desc.lpSurface + (size_t)(y + rect->top) * desc.lPitch + (size_t)rect->left * 4, FRAME_W * 4);
        }
        ok = TRUE;
    }
    unlock(source, NULL);
    if (!g_grab_noted) {
        g_grab_noted = 1;
        note("surface %ldx%ld bits %lu caps %08lx, reading it %s", (long)desc.dwWidth, (long)desc.dwHeight,
             desc.ddpfPixelFormat.dwRGBBitCount, desc.ddsCaps.dwCaps, ok ? "directly" : "through GDI");
    }
    return ok;
}

// grabs the frame and hands it over, this is all the game thread does
static BOOL draw_upscaled(void *source, const RECT *source_rect) {
    HWND window = game_window();
    GetDCFn get_dc = (GetDCFn)(*(void ***)source)[GETDC_SLOT];
    ReleaseDCFn release_dc = (ReleaseDCFn)(*(void ***)source)[RELEASEDC_SLOT];
    RECT client;
    HDC from = NULL;
    double started;
    if (g_test_dc || g_up_state < 0 || !window || !GetClientRect(window, &client) || client.right <= 0 || client.bottom <= 0) return FALSE;
    if (source_rect->right - source_rect->left != FRAME_W || source_rect->bottom - source_rect->top != FRAME_H) return FALSE;
    if (!(GetWindowLongA(window, GWL_STYLE) & WS_CAPTION)) {
        if (g_up_state > 0 && g_up.swap) {
            EnterCriticalSection(&g_mail_lock);
            g_mail_detach = 1;
            LeaveCriticalSection(&g_mail_lock);
            SetEvent(g_mail_event);
            WaitForSingleObject(g_detached_event, 1000);
        }
        return FALSE;
    }
    if (g_up_state == 0 && !g_thread_started) {
        BITMAPINFO info;
        g_thread_started = 1;
        ZeroMemory(&info, sizeof(info));
        info.bmiHeader.biSize = sizeof(info.bmiHeader);
        info.bmiHeader.biWidth = FRAME_W;
        info.bmiHeader.biHeight = -FRAME_H;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        g_frame_dc = CreateCompatibleDC(NULL);
        g_frame_bitmap = CreateDIBSection(NULL, &info, DIB_RGB_COLORS, (void **)&g_frame_pixels, NULL, 0);
        g_mail = (BYTE *)malloc(FRAME_BYTES);
        g_work = (BYTE *)malloc(FRAME_BYTES);
        g_last = (BYTE *)calloc(FRAME_BYTES, 1);
        g_mail_event = CreateEventA(NULL, FALSE, FALSE, NULL);
        g_detached_event = CreateEventA(NULL, FALSE, FALSE, NULL);
        if (!g_frame_dc || !g_frame_bitmap || !g_mail || !g_work || !g_last || !g_mail_event || !g_detached_event) {
            note("upscale off, no frame memory");
            g_up_state = -1;
            return FALSE;
        }
        SelectObject(g_frame_dc, g_frame_bitmap);
        InitializeCriticalSection(&g_mail_lock);
        if (!CreateThread(NULL, 0, filter_thread, NULL, 0, NULL)) {
            note("upscale off, no thread");
            g_up_state = -1;
            return FALSE;
        }
    }
    // the plain sharp draw covers the moment the shaders are loading
    if (g_up_state != 1) return FALSE;
    started = now_ms();
    if (!grab_by_lock(source, source_rect)) {
        if (FAILED(get_dc(source, &from))) return FALSE;
        BitBlt(g_frame_dc, 0, 0, FRAME_W, FRAME_H, from, source_rect->left, source_rect->top, SRCCOPY);
        release_dc(source, from);
        GdiFlush();
    }
    EnterCriticalSection(&g_mail_lock);
    memcpy(g_mail, g_frame_pixels, FRAME_BYTES);
    g_mail_window = window;
    g_mail_w = (UINT)client.right;
    g_mail_h = (UINT)client.bottom;
    LeaveCriticalSection(&g_mail_lock);
    SetEvent(g_mail_event);
    {
        double grab = now_ms() - started;
        g_grab_ms += grab;
        g_grabs++;
        if (grab > g_grab_peak) g_grab_peak = grab;
    }
    return TRUE;
}

static BOOL draw_sharp(void *source, const RECT *source_rect) {
    HWND window = game_window();
    GetDCFn get_dc = (GetDCFn)(*(void ***)source)[GETDC_SLOT];
    ReleaseDCFn release_dc = (ReleaseDCFn)(*(void ***)source)[RELEASEDC_SLOT];
    RECT client;
    HDC from = NULL, to;
    int sx, sy, sw, sh, cw, ch, n;
    BOOL ok;
    if (g_test_dc) {
        SetRect(&client, 0, 0, g_test_w, g_test_h);
    } else if (!window || !GetClientRect(window, &client)) {
        return FALSE;
    }
    cw = client.right;
    ch = client.bottom;
    if (cw <= 0 || ch <= 0 || !source_rect) return FALSE;
    sx = source_rect->left;
    sy = source_rect->top;
    sw = source_rect->right - sx;
    sh = source_rect->bottom - sy;
    if (sw <= 0 || sh <= 0) return FALSE;
    if (FAILED(get_dc(source, &from))) return FALSE;
    to = g_test_dc ? g_test_dc : GetDC(window);
    if (!to) {
        release_dc(source, from);
        return FALSE;
    }
    n = (cw + sw - 1) / sw;
    if ((ch + sh - 1) / sh > n) n = (ch + sh - 1) / sh;
    if (n * sw == cw && n * sh == ch) {
        SetStretchBltMode(to, COLORONCOLOR);
        ok = StretchBlt(to, 0, 0, cw, ch, from, sx, sy, sw, sh, SRCCOPY);
    } else {
        ok = ensure_middle(to, n * sw, n * sh);
        if (ok) {
            SetStretchBltMode(g_mid_dc, COLORONCOLOR);
            ok = StretchBlt(g_mid_dc, 0, 0, n * sw, n * sh, from, sx, sy, sw, sh, SRCCOPY);
        }
        if (ok) {
            SetStretchBltMode(to, HALFTONE);
            SetBrushOrgEx(to, 0, 0, NULL);
            ok = StretchBlt(to, 0, 0, cw, ch, g_mid_dc, 0, 0, n * sw, n * sh, SRCCOPY);
        }
    }
    if (!g_test_dc) ReleaseDC(window, to);
    release_dc(source, from);
    if (ok) {
        g_sharp_frames++;
        if (cw != g_last_w || ch != g_last_h) {
            note("drawing sharp, picture %dx%d window %dx%d frames %ld", sw, sh, cw, ch, g_sharp_frames);
            g_last_w = cw;
            g_last_h = ch;
        }
    }
    return ok;
}

static HRESULT WINAPI hook_blt(void *dest, LPRECT dest_rect, void *source, LPRECT source_rect, DWORD flags, LPDDBLTFX fx) {
    Hooked *hook = find_hook(dest);
    long calls;
    BltFn original = hook ? hook->blt : NULL;
    if (!hook) return DDERR_GENERIC;
    calls = ++hook->blt_calls;
    if (calls <= 2) {
        note("blt table %p to primary %d source %d dest %ldx%ld from %ldx%ld flags %08lx", hook->table, is_primary(dest), source != NULL,
             dest_rect ? dest_rect->right - dest_rect->left : -1, dest_rect ? dest_rect->bottom - dest_rect->top : -1,
             source_rect ? source_rect->right - source_rect->left : -1, source_rect ? source_rect->bottom - source_rect->top : -1, flags);
    }
    if (!g_inside && source && dest_rect && is_primary(dest)) {
        RECT whole;
        const RECT *from = source_rect;
        if (!from && surface_rect(source, &whole)) from = &whole;
        if (!from) {
            if (g_fallbacks++ < 5) note("could not size the picture, used the normal stretch");
            return original(dest, dest_rect, source, source_rect, flags, fx);
        }
        {
            // once the window has our picture on it, normal size has to keep going through it too
            BOOL differs = dest_rect->right - dest_rect->left != from->right - from->left || dest_rect->bottom - dest_rect->top != from->bottom - from->top;
            g_blts++;
            if (differs || g_up_state > 0) {
                g_inside = 1;
                if (draw_upscaled(source, from)) {
                    g_inside = 0;
                    return DD_OK;
                }
                if (differs && draw_sharp(source, from)) {
                    g_inside = 0;
                    return DD_OK;
                }
                g_inside = 0;
                if (differs && g_fallbacks++ < 5) note("sharp draw failed, used the normal stretch");
            }
        }
    }
    return original(dest, dest_rect, source, source_rect, flags, fx);
}

static HRESULT WINAPI hook_fast(void *dest, DWORD x, DWORD y, void *source, LPRECT source_rect, DWORD flags) {
    Hooked *hook = find_hook(dest);
    if (!hook) return DDERR_GENERIC;
    if (++hook->fast_calls <= 3) note("bltfast table %p to primary %d", hook->table, is_primary(dest));
    return hook->fast(dest, x, y, source, source_rect, flags);
}

static HRESULT WINAPI hook_flip(void *dest, void *other, DWORD flags) {
    Hooked *hook = find_hook(dest);
    if (!hook) return DDERR_GENERIC;
    if (++hook->flip_calls <= 3) note("flip table %p", hook->table);
    return hook->flip(dest, other, flags);
}

static void hook_table(void *surface) {
    void **table = *(void ***)surface;
    Hooked *h;
    int i;
    for (i = 0; i < g_count; i++)
        if (g_hooks[i].table == table) return;
    if (g_count >= VERSIONS) return;
    h = &g_hooks[g_count];
    h->table = table;
    // publish the originals before the slots change, the engine draws on another thread
    h->blt = (BltFn)table[BLT_SLOT];
    h->fast = (BltFastFn)table[BLTFAST_SLOT];
    h->flip = (FlipFn)table[FLIP_SLOT];
    g_count++;
    patch_slot(table, BLT_SLOT, (void *)hook_blt);
    patch_slot(table, BLTFAST_SLOT, (void *)hook_fast);
    patch_slot(table, FLIP_SLOT, (void *)hook_flip);
    note("hooked surface table %p", table);
}

// lets the test program read exactly what would go to the window
__declspec(dllexport) void WINAPI RandoSharpTestTarget(HDC target, int w, int h) {
    g_test_dc = target;
    g_test_w = w;
    g_test_h = h;
}

// returns how many surface tables are hooked
__declspec(dllexport) int WINAPI RandoSharpInstall(void) {
    static const IID *ids[VERSIONS] = {&IID_IDirectDrawSurface, &IID_IDirectDrawSurface2, &IID_IDirectDrawSurface3, &IID_IDirectDrawSurface4, &IID_IDirectDrawSurface7};
    HMODULE module;
    CreateExFn create;
    IDirectDraw7 *draw = NULL;
    IDirectDrawSurface7 *primary = NULL;
    DDSURFACEDESC2 desc;
    HRESULT hr;
    int i;
    if (g_installed) return g_count;
    g_installed = 1;
    // the game's Ruby frees this dll when its Win32API object is collected and the hooks live in here
    {
        HMODULE self;
        if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, (LPCSTR)RandoSharpInstall, &self)) {
            note("could not pin the dll, staying off");
            return 0;
        }
    }
    module = LoadLibraryA("ddraw.dll");
    create = module ? (CreateExFn)GetProcAddress(module, "DirectDrawCreateEx") : NULL;
    if (!create) {
        note("no DirectDrawCreateEx");
        return 0;
    }
    hr = create(NULL, (void **)&draw, &IID_IDirectDraw7, NULL);
    if (FAILED(hr)) {
        note("create failed %08lx", hr);
        return 0;
    }
    hr = IDirectDraw7_SetCooperativeLevel(draw, NULL, DDSCL_NORMAL);
    ZeroMemory(&desc, sizeof(desc));
    desc.dwSize = sizeof(desc);
    desc.dwFlags = DDSD_CAPS;
    desc.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    if (SUCCEEDED(hr)) hr = IDirectDraw7_CreateSurface(draw, &desc, &primary, NULL);
    if (FAILED(hr) || !primary) {
        note("primary surface failed %08lx", hr);
        IDirectDraw7_Release(draw);
        return 0;
    }
    for (i = 0; i < VERSIONS; i++) {
        void *surface = NULL;
        if (SUCCEEDED(IDirectDrawSurface7_QueryInterface(primary, ids[i], &surface)) && surface) {
            hook_table(surface);
            ((IUnknown *)surface)->lpVtbl->Release((IUnknown *)surface);
        }
    }
    IDirectDrawSurface7_Release(primary);
    IDirectDraw7_Release(draw);
    note("installed, %d surface tables", g_count);
    return g_count;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
    return TRUE;
}
