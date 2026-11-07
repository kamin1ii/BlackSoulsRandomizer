#define MF float
#define MF2 float2
#define MF3 float3
#define MF4 float4
#define MF2x2 float2x2
#define MF3x3 float3x3
#define MF4x4 float4x4
#define MF3x4 float3x4
#define MF4x3 float4x3
static const uint2 __in = uint2(1280, 960);
static const uint2 __out = uint2(1280, 960);
uint2 GetInputSize() { return __in; }
uint2 GetOutputSize() { return __out; }
float2 GetInputPt() { return 1.0f / float2(__in); }
float2 GetOutputPt() { return 1.0f / float2(__out); }
uint2 Rmp8x8(uint a) { return uint2(a & 7u, (a >> 3u) & 7u); }
float4 MulAdd(float3 x, float3x4 y, float4 a) { return mul(x, y) + a; }
float4 MulAdd(float4 x, float4x4 y, float4 a) { return mul(x, y) + a; }
float3 MulAdd(float4 x, float4x3 y, float3 a) { return mul(x, y) + a; }
float3 MulAdd(float3 x, float3x3 y, float3 a) { return mul(x, y) + a; }

Texture2D<float4> INPUT : register(t0);
RWTexture2D<unorm float4> OUTPUT : register(u0);
SamplerState sam : register(s0);

#define FXAA_PRESET 3
#include "FXAA.hlsli"


void Pass1(uint2 blockStart, uint3 threadId) {
	uint2 gxy = (Rmp8x8(threadId.x) << 1) + blockStart;

	const uint2 outputSize = GetOutputSize();
	if (gxy.x >= outputSize.x || gxy.y >= outputSize.y) {
		return;
	}

	float2 inputPt = GetInputPt();
	uint i, j;

	float3 src[4][4];
	[unroll]
	for (i = 0; i <= 2; i += 2) {
		[unroll]
		for (j = 0; j <= 2; j += 2) {
			float2 tpos = (gxy + uint2(i, j)) * inputPt;
			const float4 sr = INPUT.GatherRed(sam, tpos);
			const float4 sg = INPUT.GatherGreen(sam, tpos);
			const float4 sb = INPUT.GatherBlue(sam, tpos);

			// w z
			// x y
			src[i][j] = float3(sr.w, sg.w, sb.w);
			src[i][j + 1] = float3(sr.x, sg.x, sb.x);
			src[i + 1][j] = float3(sr.z, sg.z, sb.z);
			src[i + 1][j + 1] = float3(sr.y, sg.y, sb.y);
		}
	}

	[unroll]
	for (i = 0; i <= 1; ++i) {
		[unroll]
		for (j = 0; j <= 1; ++j) {
			uint2 destPos = gxy + uint2(i, j);
			OUTPUT[destPos] = float4(FXAA(src, i + 1, j + 1, INPUT, sam, (destPos + 0.5f) * inputPt, inputPt), 1);
		}
	}
}
[numthreads(64, 1, 1)]
void __Main(uint3 tid : SV_GroupThreadID, uint3 gid : SV_GroupID) {
	Pass1(gid.xy * uint2(16, 16), tid);
}
