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
RWTexture2D<float4> tex1 : register(u0);
RWTexture2D<float4> tex2 : register(u1);
SamplerState sam : register(s0);

void Pass1(uint2 blockStart, uint3 threadId) {
	uint2 gxy = (Rmp8x8(threadId.x) << 1) + blockStart;
	uint2 inputSize = GetInputSize();
	if (gxy.x >= inputSize.x || gxy.y >= inputSize.y) {
		return;
	}

	float2 inputPt = GetInputPt();
	uint i, j;

	MF3 src[4][4];
	[unroll]
	for (i = 0; i <= 2; i += 2) {
		[unroll]
		for (j = 0; j <= 2; j += 2) {
			float2 tpos = (gxy + uint2(i, j)) * inputPt;
			const MF4 sr = INPUT.GatherRed(sam, tpos);
			const MF4 sg = INPUT.GatherGreen(sam, tpos);
			const MF4 sb = INPUT.GatherBlue(sam, tpos);

			// w z
			// x y
			src[i][j] = MF3(sr.w, sg.w, sb.w);
			src[i][j + 1] = MF3(sr.x, sg.x, sb.x);
			src[i + 1][j] = MF3(sr.z, sg.z, sb.z);
			src[i + 1][j + 1] = MF3(sr.y, sg.y, sb.y);
		}
	}

	[unroll]
	for (i = 1; i <= 2; ++i) {
		[unroll]
		for (j = 1; j <= 2; ++j) {
			uint2 destPos = gxy + uint2(i - 1, j - 1);

			if (i != 1 || j != 1) {
				if (destPos.x >= inputSize.x || destPos.y >= inputSize.y) {
					continue;
				}
			}

			MF4 target1 = { -0.55533427, -0.05231614, -0.032685343, -0.027457517 };
			target1 = MulAdd(src[i - 1][j - 1], MF3x4(-0.2676983, -0.1694746, 0.7231928, -0.050193843, 0.1850188, -0.4749505, 0.07632266, 0.17824799, 0.026348969, -0.213702, -0.16420218, -0.066780016), target1);
			target1 = MulAdd(src[i - 1][j], MF3x4(-0.09888135, -0.079641104, 0.51160043, 0.53629893, -0.1368544, -0.07092336, 0.18622977, 0.6388427, 0.19499005, 0.06811229, -0.31991923, 0.088302985), target1);
			target1 = MulAdd(src[i - 1][j + 1], MF3x4(0.06487055, -0.1591197, -0.29304126, -0.428903, 0.1966732, 0.11229865, 0.089009434, 0.23463708, -0.22231965, -0.008649182, 0.3317394, 0.10976113), target1);
			target1 = MulAdd(src[i][j - 1], MF3x4(0.40386826, -0.09486362, -0.058931742, -0.1341693, -0.28993917, -0.09050739, 0.28094417, 0.31630108, -0.02661985, -0.24368657, 0.096867286, 0.05391612), target1);
			target1 = MulAdd(src[i][j], MF3x4(0.05631564, 0.34576723, -0.5587978, 0.16213721, 0.12679785, 0.18991663, -0.24762277, -0.33682153, -0.22863568, 0.20517963, 0.20418519, 0.12087338), target1);
			target1 = MulAdd(src[i][j + 1], MF3x4(-0.17579688, 0.18395603, -0.014987654, 0.30243605, -0.12778279, -0.07003458, -0.5353068, -0.39372426, 0.2676877, 0.255503, -0.29737592, -0.30513638), target1);
			target1 = MulAdd(src[i + 1][j - 1], MF3x4(0.799834, -0.023603538, 0.19820727, -0.11204286, -0.1566225, -0.1937577, -0.030266436, -0.10107911, 0.023661222, 0.16879195, 0.046644643, 0.09485681), target1);
			target1 = MulAdd(src[i + 1][j], MF3x4(-0.014675849, -0.110290475, -0.28381273, -0.06814732, 0.2067597, 0.20925248, -0.24068354, -0.5096708, -0.09384791, 0.10593733, 0.0672362, -0.06924161), target1);
			target1 = MulAdd(src[i + 1][j + 1], MF3x4(0.05908883, 0.099426664, -0.20916614, -0.17044452, -0.091960385, 0.3218613, 0.41635308, -0.36125022, -0.012630896, -0.37540653, 0.018497325, -0.100674420), target1);

			MF4 target2 = { 0.029685514, 0.066621915, 0.03600017, -0.03497038 };
			target2 = MulAdd(src[i - 1][j - 1], MF3x4(0.09844753, -0.19389127, 0.029695928, 0.3805915, 0.1353029, 0.027786473, 0.15621242, 0.09383762, -0.1097243, 0.021245124, -0.016402386, 0.09129394), target2);
			target2 = MulAdd(src[i - 1][j], MF3x4(0.3038283, 0.03778846, 0.1898852, 0.23949303, -0.34829387, 0.20485392, 0.60560244, 0.4089768, -0.260066, 0.42611003, 0.19227165, 0.03948586), target2);
			target2 = MulAdd(src[i - 1][j + 1], MF3x4(-0.033990905, 0.17583308, -0.2235879, 0.47376296, -0.1001787, 0.72851896, -0.056391567, -0.056544185, 0.0966166, -0.016663829, -0.15151545, -0.14227313), target2);
			target2 = MulAdd(src[i][j - 1], MF3x4(-0.16544957, 0.05889452, -0.3277256, -0.42792717, 0.32491356, -0.39113912, 0.16600312, -0.3097514, 0.27907088, -0.22553465, 0.048548058, -0.08310438), target2);
			target2 = MulAdd(src[i][j], MF3x4(0.03992136, 0.17895368, 0.16562924, -0.536188, -0.25868654, -0.4869832, 0.2591772, -0.5191932, 0.020162001, -0.41568524, 0.4776641, 0.019298514), target2);
			target2 = MulAdd(src[i][j + 1], MF3x4(0.14911795, -0.5984171, -0.18241958, 0.5472136, -0.69194865, 0.033839397, 0.13408412, 0.09503547, -0.21318413, 0.53743845, 0.080091774, -0.1369053), target2);
			target2 = MulAdd(src[i + 1][j - 1], MF3x4(-0.038978565, 0.40742934, 0.20107205, -0.3550106, 0.227634, -0.16101603, -0.45037574, 0.23192371, 0.17923234, -0.13692904, 0.10395048, 0.3124129), target2);
			target2 = MulAdd(src[i + 1][j], MF3x4(-0.059144646, -0.22531863, -0.024704054, -0.20749553, 0.58086175, -0.32206532, -0.5130457, -0.14057957, 0.24317528, 0.088735096, -0.44098017, -0.16980846), target2);
			target2 = MulAdd(src[i + 1][j + 1], MF3x4(-0.30321437, 0.17502202, 0.1910563, -0.10118702, 0.1465326, 0.3852395, -0.31210947, 0.18236226, -0.23306467, -0.28551704, -0.2982589, 0.072740674), target2);

			tex1[destPos] = target1;
			tex2[destPos] = target2;
		}
	}
}


[numthreads(64, 1, 1)]
void __Main(uint3 tid : SV_GroupThreadID, uint3 gid : SV_GroupID) {
	Pass1(gid.xy * uint2(16, 16), tid);
}
