# Upscale shaders

The compiled shaders in game/upscale come from four effects that ship with Magpie (github.com/Blinue/Magpie), which is licensed under the GNU General Public License version 3. They keep that license, the full text is in COPYING next to this file.

- CuNNy 8x32 NVL by funnyplanter (github.com/funnyplanter/CuNNy), GPL version 3 or later
- Anime4K Restore CNN Soft L by bloc97 (github.com/bloc97/Anime4K), ported to HLSL by Magpie
- Adaptive Sharpen by bacondither, from the libretro slang shaders (github.com/libretro/slang-shaders), ported by Magpie
- FXAA from the libretro slang shaders, ported by Magpie

source holds the Magpie effect files as they were used, their editor only include StubDefs.hlsli is left out since the build drops it. generated holds the exact HLSL each file in game/upscale was compiled from. tools/build_upscale.py turns the first into the second and compiles them with fxc.

Only the shaders fall under this license. The rest of the randomizer is separate work that loads them at run time.
