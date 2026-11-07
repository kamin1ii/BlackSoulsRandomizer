// Runs the filter chain on a saved 640x480 frame without any window, writes the result and times it
// upscale_test <shader folder> <in.bmp> <out.bmp>
#include "upscale_engine.h"

#define LARGE_ENOUGH 400

static BYTE *load_bmp(const char *path, int *w, int *h) {
    BITMAPFILEHEADER head;
    BITMAPINFOHEADER info;
    FILE *f = fopen(path, "rb");
    BYTE *pixels;
    int y;
    if (!f) return NULL;
    fread(&head, sizeof(head), 1, f);
    fread(&info, sizeof(info), 1, f);
    if (info.biBitCount != 32 || info.biHeight >= 0) { fclose(f); return NULL; }
    *w = info.biWidth;
    *h = -info.biHeight;
    fseek(f, head.bfOffBits, SEEK_SET);
    pixels = (BYTE *)malloc((size_t)*w * *h * 4);
    for (y = 0; y < *h; y++) fread(pixels + (size_t)y * *w * 4, *w * 4, 1, f);
    fclose(f);
    return pixels;
}

static BOOL save_final(Upscale *u, const char *path) {
    int index = u->final_index;
    D3D11_TEXTURE2D_DESC desc;
    ID3D11Texture2D *staging = NULL;
    D3D11_MAPPED_SUBRESOURCE map;
    BITMAPFILEHEADER head;
    BITMAPINFOHEADER info;
    FILE *f;
    UINT y, x;
    ID3D11Texture2D_GetDesc(u->texture[index], &desc);
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    if (FAILED(ID3D11Device_CreateTexture2D(u->device, &desc, NULL, &staging))) return FALSE;
    ID3D11DeviceContext_CopyResource(u->context, (ID3D11Resource *)staging, (ID3D11Resource *)u->texture[index]);
    if (FAILED(ID3D11DeviceContext_Map(u->context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &map))) return FALSE;
    f = fopen(path, "wb");
    ZeroMemory(&head, sizeof(head));
    ZeroMemory(&info, sizeof(info));
    head.bfType = 0x4D42;
    head.bfOffBits = sizeof(head) + sizeof(info);
    head.bfSize = head.bfOffBits + desc.Width * desc.Height * 4;
    info.biSize = sizeof(info);
    info.biWidth = desc.Width;
    info.biHeight = -(LONG)desc.Height;
    info.biPlanes = 1;
    info.biBitCount = 32;
    fwrite(&head, sizeof(head), 1, f);
    fwrite(&info, sizeof(info), 1, f);
    for (y = 0; y < desc.Height; y++) {
        const BYTE *row = (const BYTE *)map.pData + y * map.RowPitch;
        for (x = 0; x < desc.Width; x++) {
            BYTE px[4];
            px[0] = row[x * 4 + 2];
            px[1] = row[x * 4 + 1];
            px[2] = row[x * 4];
            px[3] = 255;
            fwrite(px, 4, 1, f);
        }
    }
    fclose(f);
    ID3D11DeviceContext_Unmap(u->context, (ID3D11Resource *)staging, 0);
    ID3D11Texture2D_Release(staging);
    return TRUE;
}

static void wait_gpu(Upscale *u) {
    D3D11_QUERY_DESC q;
    ID3D11Query *query = NULL;
    BOOL done = FALSE;
    q.Query = D3D11_QUERY_EVENT;
    q.MiscFlags = 0;
    ID3D11Device_CreateQuery(u->device, &q, &query);
    ID3D11DeviceContext_End(u->context, (ID3D11Asynchronous *)query);
    ID3D11DeviceContext_Flush(u->context);
    while (ID3D11DeviceContext_GetData(u->context, (ID3D11Asynchronous *)query, &done, sizeof(done), 0) != S_OK || !done) { }
    ID3D11Query_Release(query);
}

// runs the resize step into a plain texture of another size and saves it
static BOOL save_fitted(Upscale *u, UINT w, UINT h, const char *path) {
    D3D11_TEXTURE2D_DESC desc;
    int final_index = u->final_index, keep_w, keep_h;
    ID3D11Texture2D *keep;
    ZeroMemory(&desc, sizeof(desc));
    desc.Width = w;
    desc.Height = h;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS | D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(ID3D11Device_CreateTexture2D(u->device, &desc, NULL, &u->swap_texture))) return FALSE;
    if (FAILED(ID3D11Device_CreateUnorderedAccessView(u->device, (ID3D11Resource *)u->swap_texture, NULL, &u->swap_uav))) return FALSE;
    u->swap_w = w;
    u->swap_h = h;
    up_draw_to_back(u, final_index);
    keep = u->texture[final_index];
    keep_w = u->tex_w[final_index];
    keep_h = u->tex_h[final_index];
    u->texture[final_index] = u->swap_texture;
    save_final(u, path);
    u->texture[final_index] = keep;
    u->tex_w[final_index] = keep_w;
    u->tex_h[final_index] = keep_h;
    return TRUE;
}

int main(int argc, char **argv) {
    static Upscale u;
    LARGE_INTEGER freq, a, b, c;
    BYTE *picture;
    int w, h, i;
    if (argc < 4) return 2;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&a);
    if (!up_create(&u, argv[1])) {
        printf("create failed %s\n", u.error);
        return 1;
    }
    QueryPerformanceCounter(&b);
    printf("loaded %d textures %d passes in %.0f ms\n", u.texture_count, u.pass_count, (b.QuadPart - a.QuadPart) * 1000.0 / freq.QuadPart);
    picture = load_bmp(argv[2], &w, &h);
    if (!picture || w != 640 || h != 480) {
        printf("need a 640x480 32 bit top down bmp\n");
        return 1;
    }
    up_run(&u, picture, 640 * 4);
    wait_gpu(&u);
    QueryPerformanceCounter(&a);
    for (i = 0; i < LARGE_ENOUGH / 4; i++) {
        up_run(&u, picture, 640 * 4);
        wait_gpu(&u);
    }
    QueryPerformanceCounter(&c);
    printf("%.2f ms per frame on the graphics card\n", (c.QuadPart - a.QuadPart) * 1000.0 / freq.QuadPart / (LARGE_ENOUGH / 4));
    if (!save_final(&u, argv[3])) {
        printf("could not save\n");
        return 1;
    }
    if (argc > 4 && !save_fitted(&u, 1000, 750, argv[4])) {
        printf("could not resize\n");
        return 1;
    }
    printf("UPSCALE TEST DONE\n");
    return 0;
}
