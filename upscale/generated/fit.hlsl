// Last step when the window is not exactly 2x, a Catmull-Rom resize of the upscaled picture
cbuffer Sizes : register(b0) {
    float2 sourcePt;
    float2 destPt;
    uint2 destSize;
    uint2 pad;
};
Texture2D<float4> Picture : register(t0);
RWTexture2D<unorm float4> Output : register(u0);
SamplerState Linear : register(s0);

[numthreads(32, 32, 1)]
void __Main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= destSize.x || id.y >= destSize.y) return;
    float2 uv = (float2(id.xy) + 0.5f) * destPt;
    float2 size = 1.0f / sourcePt;
    float2 at = uv * size - 0.5f;
    float2 cell = floor(at);
    float2 f = at - cell;
    float2 w0 = f * (-0.5f + f * (1.0f - 0.5f * f));
    float2 w1 = 1.0f + f * f * (-2.5f + 1.5f * f);
    float2 w2 = f * (0.5f + f * (2.0f - 1.5f * f));
    float2 w3 = f * f * (-0.5f + 0.5f * f);
    float2 w12 = w1 + w2;
    float2 p0 = (cell - 0.5f) * sourcePt;
    float2 p3 = (cell + 2.5f) * sourcePt;
    float2 p12 = (cell + 0.5f + w2 / w12) * sourcePt;
    float3 c = 0;
    c += Picture.SampleLevel(Linear, float2(p12.x, p0.y), 0).rgb * w12.x * w0.y;
    c += Picture.SampleLevel(Linear, float2(p0.x, p12.y), 0).rgb * w0.x * w12.y;
    c += Picture.SampleLevel(Linear, p12, 0).rgb * w12.x * w12.y;
    c += Picture.SampleLevel(Linear, float2(p3.x, p12.y), 0).rgb * w3.x * w12.y;
    c += Picture.SampleLevel(Linear, float2(p12.x, p3.y), 0).rgb * w12.x * w3.y;
    float weight = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    Output[id.xy] = float4(saturate(c / weight), 1.0f);
}
