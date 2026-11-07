# Turns the Magpie effect chain into plain compute shaders for a fixed 640x480 picture
# python tools/build_upscale.py <Magpie effects folder> [--compile]
# Writes native/build/upscale/*.hlsl, then with --compile game/upscale/*.cso and game/upscale/pipeline.txt
import math
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EFFECTS = Path(sys.argv[1])
BUILD = ROOT / "native" / "build" / "upscale"
OUT = ROOT / "game" / "upscale"
FXC = r"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe"
CHAIN = ["CuNNy2/CuNNy-8x32-NVL.hlsl", "Anime4K/Anime4K_Restore_Soft_L.hlsl", "Sharpen/AdaptiveSharpen.hlsl", "FXAA/FXAA_Medium.hlsl"]
SOURCE = (640, 480)
BETWEEN = "R16G16B16A16_FLOAT"
FINAL = "R8G8B8A8_UNORM"
FORMAT_IDS = {"R8G8B8A8_UNORM": 28, "R16G16B16A16_FLOAT": 10, "R32G32B32A32_FLOAT": 2, "R16G16B16A16_UNORM": 11, "R8_UNORM": 61, "R16_FLOAT": 54, "R16G16_FLOAT": 34}

PREAMBLE = """#define MF float
#define MF2 float2
#define MF3 float3
#define MF4 float4
#define MF2x2 float2x2
#define MF3x3 float3x3
#define MF4x4 float4x4
#define MF3x4 float3x4
#define MF4x3 float4x3
static const uint2 __in = uint2(%d, %d);
static const uint2 __out = uint2(%d, %d);
uint2 GetInputSize() { return __in; }
uint2 GetOutputSize() { return __out; }
float2 GetInputPt() { return 1.0f / float2(__in); }
float2 GetOutputPt() { return 1.0f / float2(__out); }
uint2 Rmp8x8(uint a) { return uint2(a & 7u, (a >> 3u) & 7u); }
float4 MulAdd(float3 x, float3x4 y, float4 a) { return mul(x, y) + a; }
float4 MulAdd(float4 x, float4x4 y, float4 a) { return mul(x, y) + a; }
float3 MulAdd(float4 x, float4x3 y, float3 a) { return mul(x, y) + a; }
float3 MulAdd(float3 x, float3x3 y, float3 a) { return mul(x, y) + a; }
"""


def parse(path):
    """Splits a Magpie effect into blocks, each a list of directives and the code after them."""
    blocks = []
    directives = None
    code = []
    for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if line.startswith("//!"):
            if directives is None or code:
                if directives is not None:
                    blocks.append((directives, "\n".join(code)))
                directives = []
                code = []
            directives.append(line[3:].strip())
        elif directives is not None:
            code.append(line)
    if directives is not None:
        blocks.append((directives, "\n".join(code)))
    return blocks


def value(directives, name):
    for d in directives:
        if d == name or d.startswith(name + " "):
            return d[len(name):].strip()
    return None


def size_of(expr, width, height):
    return int(eval(expr.replace("INPUT_WIDTH", str(width)).replace("INPUT_HEIGHT", str(height))))


textures = [("INPUT", SOURCE[0], SOURCE[1], 87)]
passes = []
current = 0
current_size = SOURCE
for number, name in enumerate(CHAIN):
    path = EFFECTS / name
    local = {"INPUT": current}
    samplers = []
    params = []
    common = []
    effect_passes = []
    out_size = current_size
    for directives, code in parse(path):
        kind = directives[0].split()[0]
        if kind == "TEXTURE":
            tex = re.search(r"Texture2D\s+(\w+)\s*;", code).group(1)
            if tex == "INPUT":
                continue
            w, h = value(directives, "WIDTH"), value(directives, "HEIGHT")
            w, h = size_of(w, *current_size), size_of(h, *current_size)
            fmt = value(directives, "FORMAT")
            if tex == "OUTPUT":
                out_size = (w, h)
                fmt = FINAL if number == len(CHAIN) - 1 else BETWEEN
            textures.append((f"e{number}_{tex}", w, h, FORMAT_IDS[fmt]))
            local[tex] = len(textures) - 1
        elif kind == "SAMPLER":
            samplers.append((re.search(r"SamplerState\s+(\w+)\s*;", code).group(1), value(directives, "FILTER")))
        elif kind == "PARAMETER":
            params.append((re.search(r"float\s+(\w+)\s*;", code).group(1), value(directives, "DEFAULT")))
        elif kind == "COMMON":
            common.append(code)
        elif kind == "PASS":
            effect_passes.append((int(value(directives, "PASS")), directives, code))
    for pass_number, directives, code in sorted(effect_passes, key=lambda p: p[0]):
        ins = [t.strip() for t in value(directives, "IN").split(",")]
        outs = [t.strip() for t in value(directives, "OUT").split(",")]
        block = value(directives, "BLOCK_SIZE")
        threads = int(value(directives, "NUM_THREADS") or 1)
        bw, bh = (int(x) for x in (block.split(",") * 2)[:2])
        src = [PREAMBLE % (current_size + out_size)]
        src += [f"static const float {p} = {v}f;" for p, v in params]
        for i, tex in enumerate(ins):
            src.append(f"Texture2D<float4> {tex} : register(t{i});")
        for i, tex in enumerate(outs):
            fmt = textures[local[tex]][3]
            kind_name = "unorm float4" if fmt in (28, 11, 61) else "float4"
            src.append(f"RWTexture2D<{kind_name}> {tex} : register(u{i});")
        for i, (sampler, _) in enumerate(samplers):
            src.append(f"SamplerState {sampler} : register(s{i});")
        src += common
        src.append(code)
        src.append(f"[numthreads({threads}, 1, 1)]\nvoid __Main(uint3 tid : SV_GroupThreadID, uint3 gid : SV_GroupID) {{\n"
                   f"\tPass{pass_number}(gid.xy * uint2({bw}, {bh}), tid);\n}}\n")
        file_name = f"e{number}_p{pass_number}"
        text = "\n".join(src).replace('#include "../StubDefs.hlsli"', "")
        BUILD.mkdir(parents=True, exist_ok=True)
        (BUILD / (file_name + ".hlsl")).write_text(text, encoding="utf-8")
        first = textures[local[outs[0]]]
        passes.append(dict(name=file_name, include=str(path.parent), groups=(math.ceil(first[1] / bw), math.ceil(first[2] / bh)),
                           srv=[local[t] for t in ins], uav=[local[t] for t in outs], samplers=[1 if f == "LINEAR" else 0 for _, f in samplers]))
    current = local["OUTPUT"]
    current_size = out_size
    print(name, "passes", len(effect_passes), "out", out_size)

print(len(passes), "passes", len(textures), "textures, final", textures[current])

lines = [f"textures {len(textures)}"]
lines += [f"{w} {h} {fmt}" for _, w, h, fmt in textures]
lines.append(f"passes {len(passes)}")
for p in passes:
    lines.append(" ".join(str(x) for x in [p["name"], p["groups"][0], p["groups"][1], len(p["srv"]), *p["srv"], len(p["uav"]), *p["uav"], len(p["samplers"]), *p["samplers"]]))
lines.append(f"final {current}")

if "--compile" in sys.argv:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "pipeline.txt").write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")

    def compile_pass(p):
        target = OUT / (p["name"] + ".cso")
        hlsl = BUILD / (p["name"] + ".hlsl")
        if target.exists() and target.stat().st_mtime > hlsl.stat().st_mtime:
            return p["name"], "kept"
        result = subprocess.run([FXC, "/nologo", "/T", "cs_5_0", "/E", "__Main", "/O1", "/I", p["include"], "/Fo", str(target), str(hlsl)], capture_output=True, text=True, errors="replace")
        if result.returncode:
            return p["name"], "FAILED " + result.stderr[-900:]
        return p["name"], f"{target.stat().st_size} bytes"

    extra = dict(name="fit", include=str(ROOT / "native"), groups=(0, 0), srv=[], uav=[], samplers=[])
    fit_src = ROOT / "native" / "fit.hlsl"
    (BUILD / "fit.hlsl").write_text(fit_src.read_text(encoding="utf-8"), encoding="utf-8")
    with ThreadPoolExecutor(6) as pool:
        for name, status in pool.map(compile_pass, passes + [extra]):
            print(name, status, flush=True)
