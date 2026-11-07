// Runs the compiled filter chain on a 640x480 picture with Direct3D 11 compute shaders
// The test program reads the result back, the game presents it to its own window
#ifndef UPSCALE_ENGINE_H
#define UPSCALE_ENGINE_H
#define COBJMACROS
#define CINTERFACE
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define UP_MAX_TEXTURES 40
#define UP_MAX_PASSES 24
#define UP_MAX_BIND 10

typedef struct {
    ID3D11ComputeShader *shader;
    UINT groups_x, groups_y;
    int srv_count, uav_count, sampler_count;
    int srv[UP_MAX_BIND], uav[UP_MAX_BIND], sampler[UP_MAX_BIND];
} UpPass;

typedef struct {
    float source_pt[2], dest_pt[2];
    UINT dest_size[2], pad[2];
} UpFitSizes;

typedef struct {
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    ID3D11Texture2D *texture[UP_MAX_TEXTURES];
    ID3D11ShaderResourceView *srv[UP_MAX_TEXTURES];
    ID3D11UnorderedAccessView *uav[UP_MAX_TEXTURES];
    UINT tex_w[UP_MAX_TEXTURES], tex_h[UP_MAX_TEXTURES];
    int texture_count, final_index;
    UpPass pass[UP_MAX_PASSES];
    int pass_count;
    ID3D11SamplerState *samplers[2];
    ID3D11ComputeShader *fit;
    ID3D11Buffer *fit_sizes;
    IDXGISwapChain1 *swap;
    ID3D11UnorderedAccessView *swap_uav;
    ID3D11Texture2D *swap_texture;
    HWND window;
    UINT swap_w, swap_h;
    char error[200];
} Upscale;

static void up_fail(Upscale *u, const char *what, HRESULT hr) {
    sprintf(u->error, "%s failed %08lx", what, (unsigned long)hr);
}

static BOOL up_read_file(const char *path, void **data, SIZE_T *size) {
    FILE *f = fopen(path, "rb");
    long n;
    if (!f) return FALSE;
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    *data = malloc(n);
    *size = (SIZE_T)n;
    if (!*data || fread(*data, 1, n, f) != (size_t)n) {
        fclose(f);
        return FALSE;
    }
    fclose(f);
    return TRUE;
}

static BOOL up_load_shader(Upscale *u, const char *folder, const char *name, ID3D11ComputeShader **out) {
    char path[MAX_PATH];
    void *code;
    SIZE_T size;
    HRESULT hr;
    sprintf(path, "%s\\%s.cso", folder, name);
    if (!up_read_file(path, &code, &size)) {
        sprintf(u->error, "cannot read %s", path);
        return FALSE;
    }
    hr = ID3D11Device_CreateComputeShader(u->device, code, size, NULL, out);
    free(code);
    if (FAILED(hr)) {
        up_fail(u, name, hr);
        return FALSE;
    }
    return TRUE;
}

static BOOL up_make_texture(Upscale *u, int index, UINT w, UINT h, DXGI_FORMAT format, BOOL first) {
    D3D11_TEXTURE2D_DESC desc;
    HRESULT hr;
    ZeroMemory(&desc, sizeof(desc));
    desc.Width = w;
    desc.Height = h;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = format;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | (first ? 0 : D3D11_BIND_UNORDERED_ACCESS);
    hr = ID3D11Device_CreateTexture2D(u->device, &desc, NULL, &u->texture[index]);
    if (FAILED(hr)) { up_fail(u, "texture", hr); return FALSE; }
    hr = ID3D11Device_CreateShaderResourceView(u->device, (ID3D11Resource *)u->texture[index], NULL, &u->srv[index]);
    if (FAILED(hr)) { up_fail(u, "shader view", hr); return FALSE; }
    if (!first) {
        hr = ID3D11Device_CreateUnorderedAccessView(u->device, (ID3D11Resource *)u->texture[index], NULL, &u->uav[index]);
        if (FAILED(hr)) { up_fail(u, "write view", hr); return FALSE; }
    }
    u->tex_w[index] = w;
    u->tex_h[index] = h;
    return TRUE;
}

// folder holds pipeline.txt and the compiled shaders
static BOOL up_create(Upscale *u, const char *folder) {
    static const D3D_FEATURE_LEVEL want[] = {D3D_FEATURE_LEVEL_11_0};
    char path[MAX_PATH], name[64];
    FILE *f;
    int i, j, count;
    HRESULT hr;
    D3D11_SAMPLER_DESC sampler;
    D3D11_BUFFER_DESC buffer;
    ZeroMemory(u, sizeof(*u));
    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, want, 1, D3D11_SDK_VERSION, &u->device, NULL, &u->context);
    if (FAILED(hr)) { up_fail(u, "device", hr); return FALSE; }
    sprintf(path, "%s\\pipeline.txt", folder);
    f = fopen(path, "r");
    if (!f) { sprintf(u->error, "cannot read %s", path); return FALSE; }
    if (fscanf(f, "textures %d", &u->texture_count) != 1 || u->texture_count > UP_MAX_TEXTURES) { strcpy(u->error, "bad texture list"); fclose(f); return FALSE; }
    for (i = 0; i < u->texture_count; i++) {
        unsigned w, h, format;
        if (fscanf(f, "%u %u %u", &w, &h, &format) != 3 || !up_make_texture(u, i, w, h, (DXGI_FORMAT)format, i == 0)) {
            if (!u->error[0]) strcpy(u->error, "bad texture row");
            fclose(f);
            return FALSE;
        }
    }
    if (fscanf(f, " passes %d", &u->pass_count) != 1 || u->pass_count > UP_MAX_PASSES) { strcpy(u->error, "bad pass list"); fclose(f); return FALSE; }
    for (i = 0; i < u->pass_count; i++) {
        UpPass *p = &u->pass[i];
        if (fscanf(f, "%63s %u %u", name, &p->groups_x, &p->groups_y) != 3) { strcpy(u->error, "bad pass row"); fclose(f); return FALSE; }
        fscanf(f, "%d", &count);
        p->srv_count = count;
        for (j = 0; j < count; j++) fscanf(f, "%d", &p->srv[j]);
        fscanf(f, "%d", &count);
        p->uav_count = count;
        for (j = 0; j < count; j++) fscanf(f, "%d", &p->uav[j]);
        fscanf(f, "%d", &count);
        p->sampler_count = count;
        for (j = 0; j < count; j++) fscanf(f, "%d", &p->sampler[j]);
        if (!up_load_shader(u, folder, name, &p->shader)) { fclose(f); return FALSE; }
    }
    if (fscanf(f, " final %d", &u->final_index) != 1) { strcpy(u->error, "no final texture"); fclose(f); return FALSE; }
    fclose(f);
    if (!up_load_shader(u, folder, "fit", &u->fit)) return FALSE;
    ZeroMemory(&sampler, sizeof(sampler));
    sampler.AddressU = sampler.AddressV = sampler.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler.ComparisonFunc = D3D11_COMPARISON_NEVER;
    sampler.MaxLOD = D3D11_FLOAT32_MAX;
    sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
    hr = ID3D11Device_CreateSamplerState(u->device, &sampler, &u->samplers[0]);
    if (SUCCEEDED(hr)) {
        sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        hr = ID3D11Device_CreateSamplerState(u->device, &sampler, &u->samplers[1]);
    }
    if (FAILED(hr)) { up_fail(u, "sampler", hr); return FALSE; }
    ZeroMemory(&buffer, sizeof(buffer));
    buffer.ByteWidth = sizeof(UpFitSizes);
    buffer.Usage = D3D11_USAGE_DEFAULT;
    buffer.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    hr = ID3D11Device_CreateBuffer(u->device, &buffer, NULL, &u->fit_sizes);
    if (FAILED(hr)) { up_fail(u, "constant buffer", hr); return FALSE; }
    return TRUE;
}

static void up_unbind(Upscale *u) {
    ID3D11ShaderResourceView *no_srv[UP_MAX_BIND] = {0};
    ID3D11UnorderedAccessView *no_uav[UP_MAX_BIND] = {0};
    ID3D11DeviceContext_CSSetShaderResources(u->context, 0, UP_MAX_BIND, no_srv);
    ID3D11DeviceContext_CSSetUnorderedAccessViews(u->context, 0, 8, no_uav, NULL);
}

// picture is 640x480 BGRA, top row first
static void up_run(Upscale *u, const void *picture, UINT pitch) {
    int i, j;
    ID3D11DeviceContext_UpdateSubresource(u->context, (ID3D11Resource *)u->texture[0], 0, NULL, picture, pitch, 0);
    for (i = 0; i < u->pass_count; i++) {
        UpPass *p = &u->pass[i];
        ID3D11ShaderResourceView *srv[UP_MAX_BIND];
        ID3D11UnorderedAccessView *uav[UP_MAX_BIND];
        ID3D11SamplerState *sam[UP_MAX_BIND];
        for (j = 0; j < p->srv_count; j++) srv[j] = u->srv[p->srv[j]];
        for (j = 0; j < p->uav_count; j++) uav[j] = u->uav[p->uav[j]];
        for (j = 0; j < p->sampler_count; j++) sam[j] = u->samplers[p->sampler[j]];
        ID3D11DeviceContext_CSSetShader(u->context, p->shader, NULL, 0);
        if (p->sampler_count) ID3D11DeviceContext_CSSetSamplers(u->context, 0, p->sampler_count, sam);
        ID3D11DeviceContext_CSSetShaderResources(u->context, 0, p->srv_count, srv);
        ID3D11DeviceContext_CSSetUnorderedAccessViews(u->context, 0, p->uav_count, uav, NULL);
        ID3D11DeviceContext_Dispatch(u->context, p->groups_x, p->groups_y, 1);
        up_unbind(u);
    }
}

static void up_release_swap_views(Upscale *u) {
    if (u->swap_uav) ID3D11UnorderedAccessView_Release(u->swap_uav);
    if (u->swap_texture) ID3D11Texture2D_Release(u->swap_texture);
    u->swap_uav = NULL;
    u->swap_texture = NULL;
}

static BOOL up_make_swap_views(Upscale *u) {
    HRESULT hr = IDXGISwapChain1_GetBuffer(u->swap, 0, &IID_ID3D11Texture2D, (void **)&u->swap_texture);
    if (FAILED(hr)) { up_fail(u, "back buffer", hr); return FALSE; }
    hr = ID3D11Device_CreateUnorderedAccessView(u->device, (ID3D11Resource *)u->swap_texture, NULL, &u->swap_uav);
    if (FAILED(hr)) { up_fail(u, "back buffer view", hr); return FALSE; }
    return TRUE;
}

static BOOL up_attach_window(Upscale *u, HWND window, UINT w, UINT h) {
    IDXGIDevice *dxgi = NULL;
    IDXGIAdapter *adapter = NULL;
    IDXGIFactory2 *factory = NULL;
    DXGI_SWAP_CHAIN_DESC1 desc;
    HRESULT hr;
    if (u->swap && u->window == window) {
        if (u->swap_w == w && u->swap_h == h) return TRUE;
        up_release_swap_views(u);
        ID3D11DeviceContext_Flush(u->context);
        hr = IDXGISwapChain1_ResizeBuffers(u->swap, 0, w, h, DXGI_FORMAT_UNKNOWN, 0);
        if (FAILED(hr)) { up_fail(u, "resize", hr); return FALSE; }
        u->swap_w = w;
        u->swap_h = h;
        return up_make_swap_views(u);
    }
    hr = ID3D11Device_QueryInterface(u->device, &IID_IDXGIDevice, (void **)&dxgi);
    if (SUCCEEDED(hr)) hr = IDXGIDevice_GetAdapter(dxgi, &adapter);
    if (SUCCEEDED(hr)) hr = IDXGIAdapter_GetParent(adapter, &IID_IDXGIFactory2, (void **)&factory);
    if (FAILED(hr)) { up_fail(u, "factory", hr); return FALSE; }
    ZeroMemory(&desc, sizeof(desc));
    desc.Width = w;
    desc.Height = h;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT | DXGI_USAGE_UNORDERED_ACCESS;
    desc.BufferCount = 2;
    desc.Scaling = DXGI_SCALING_STRETCH;
    desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    desc.AlphaMode = DXGI_ALPHA_MODE_IGNORE;
    hr = IDXGIFactory2_CreateSwapChainForHwnd(factory, (IUnknown *)u->device, window, &desc, NULL, NULL, &u->swap);
    if (SUCCEEDED(hr)) IDXGIFactory2_MakeWindowAssociation(factory, window, DXGI_MWA_NO_ALT_ENTER | DXGI_MWA_NO_WINDOW_CHANGES);
    IDXGIFactory2_Release(factory);
    IDXGIAdapter_Release(adapter);
    IDXGIDevice_Release(dxgi);
    if (FAILED(hr)) { up_fail(u, "swap chain", hr); return FALSE; }
    u->window = window;
    u->swap_w = w;
    u->swap_h = h;
    return up_make_swap_views(u);
}

// draws a texture into the back buffer, resizing only when the sizes differ
static void up_draw_to_back(Upscale *u, int final_index) {
    if (u->swap_w == u->tex_w[final_index] && u->swap_h == u->tex_h[final_index] && final_index == u->final_index) {
        ID3D11DeviceContext_CopyResource(u->context, (ID3D11Resource *)u->swap_texture, (ID3D11Resource *)u->texture[final_index]);
    } else {
        UpFitSizes sizes;
        ID3D11ShaderResourceView *srv = u->srv[final_index];
        ID3D11UnorderedAccessView *uav = u->swap_uav;
        sizes.source_pt[0] = 1.0f / u->tex_w[final_index];
        sizes.source_pt[1] = 1.0f / u->tex_h[final_index];
        sizes.dest_pt[0] = 1.0f / u->swap_w;
        sizes.dest_pt[1] = 1.0f / u->swap_h;
        sizes.dest_size[0] = u->swap_w;
        sizes.dest_size[1] = u->swap_h;
        sizes.pad[0] = sizes.pad[1] = 0;
        ID3D11DeviceContext_UpdateSubresource(u->context, (ID3D11Resource *)u->fit_sizes, 0, NULL, &sizes, 0, 0);
        ID3D11DeviceContext_CSSetShader(u->context, u->fit, NULL, 0);
        ID3D11DeviceContext_CSSetConstantBuffers(u->context, 0, 1, &u->fit_sizes);
        ID3D11DeviceContext_CSSetSamplers(u->context, 0, 1, &u->samplers[1]);
        ID3D11DeviceContext_CSSetShaderResources(u->context, 0, 1, &srv);
        ID3D11DeviceContext_CSSetUnorderedAccessViews(u->context, 0, 1, &uav, NULL);
        ID3D11DeviceContext_Dispatch(u->context, (u->swap_w + 31) / 32, (u->swap_h + 31) / 32, 1);
        up_unbind(u);
    }
}

// sends a texture to the window, 0 is the plain picture and final_index the filtered one
static BOOL up_present(Upscale *u, int index) {
    HRESULT hr;
    up_draw_to_back(u, index);
    hr = IDXGISwapChain1_Present(u->swap, 0, 0);
    if (FAILED(hr)) { up_fail(u, "present", hr); return FALSE; }
    return TRUE;
}

static void up_detach_window(Upscale *u) {
    up_release_swap_views(u);
    if (u->swap) IDXGISwapChain1_Release(u->swap);
    u->swap = NULL;
    u->window = NULL;
    u->swap_w = u->swap_h = 0;
    ID3D11DeviceContext_ClearState(u->context);
    ID3D11DeviceContext_Flush(u->context);
}
#endif
