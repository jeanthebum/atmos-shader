# Atmos Shader

**Warm daylight. Living skies. Water with depth.**

Atmos Shader is an original WGSL shader pack for Horizon, the Rust Minecraft client. It focuses on sunlit landscapes, volumetric clouds, reflective water and atmosphere that changes with the biome.

**Version:** 0.16.3 · **Shader API:** StratosAPI 0.1.2-dev.2 (Horizon shader API 0.2) · **Status:** experimental

## Runtime requirement

Use Horizon Nightly 2026-11-19 (commit `5ef7734`) and install [StratosAPI 0.1.2-dev.2](https://github.com/jeanthebum/stratos-api/blob/main/releases/StratosAPI-0.1.2-dev.2.hmod) as a native mod through the launcher. Let the launcher build the instance, then select Atmos in that instance's shader packs menu.

## Download

Get [`Atmos-Shader-0.16.3.hshader`](releases/Atmos-Shader-0.16.3.hshader) and its [`SHA256SUMS`](releases/SHA256SUMS). Install StratosAPI first, import the `.hshader` into that instance, and select Atmos in Shader packs. WGSL compiles for your GPU at load time. The package contains no worlds, renderer binaries or development files.

## Features

- **Daylight:** warm directional sunlight, cool skylight, Lambertian diffuse lighting, foliage transmission and filtered shadows.
- **Living skies:** a round sun, volumetric cumulus clouds, atmospheric haze and shadowed god rays.
- **Water:** procedural waves, Fresnel reflections, planar terrain mirrors, depth absorption, refraction, shallow-water clarity and golden sunset highlights.
- **Vegetation:** animated leaves, grass and flowers with anchored roots.
- **Biome atmosphere:** humid jungles, misty swamps, cool deep forests, desert heat shimmer, bright snow and subtle cherry-biome colour shifts. Biome light tint can be disabled independently.
- **Rain and puddles:** procedural rain shading, wet surfaces, refraction, sun highlights and surface impact rings.
- **Finishing:** internal HDR lighting, bloom, ACES-style tonemapping, optional exposure adaptation and a configurable camera filter. Final output is SDR.

## Performance tuning

Open **Shader packs → General → Performance preset**. New installations start on **Medium**. You can still adjust individual effects.

| Preset | What changes |
| --- | --- |
| Potato | Clear sky, with volumetric clouds, sun shafts, bloom and edge smoothing disabled. |
| Low | Adds a low-sample volumetric cloud layer. Sun shafts and contact shading stay off. |
| Medium | Adds more cloud detail, contact shading and a short sun shaft pass. |
| High | Increases sky and shaft sampling and allows detailed clouds in water reflections. |
| NASA | Uses the largest cloud and atmospheric sampling budgets. |

## Source layout

The `shaders/` directory is the complete pack: **18 WGSL files, one manifest and two required procedural PNG textures**.

| Files | Purpose |
| --- | --- |
| `horizon-shaders.toml` | Stages, textures, material tags, settings pages and individual quality controls |
| `palette.wgsl`, `environment.wgsl` | Lighting palette and biome/weather response |
| `sky.wgsl`, `density.wgsl` | Sky and cloud-density model |
| `material.wgsl`, `vertex.wgsl` | Terrain/foliage lighting and vegetation motion |
| `water.wgsl`, `weather.wgsl` | Water optics, rain and liquid droplet shading |
| `post/` | Clouds, reconstruction, god rays, heat shimmer, bloom, grading and edge smoothing |
| `tonemap.wgsl` | Final display transform |
| `cloud-volume.png`, `density-noise.png` | Procedural rendering data; required, not showcase images |

The manifest retains the internal ID `afterglow_hdr` for compatibility with earlier saved settings. The public name is **Atmos Shader**.

## Validate and package

Use the `horizon-shader` tool from the matching Horizon Nightly.

```sh
horizon-shader check shaders
horizon-shader pack shaders --out Atmos-Shader-0.16.3.hshader
```

Install the resulting `.hshader` through the compatible Horizon client's shader-pack menu. Package only `shaders/`; repository documentation and Git files do not belong inside the pack.

The cloud volume uses a 71-cubed RGBA atlas to stay below Horizon's 1 MiB PNG upload limit; its four channels and wrapped slice gutters are retained.

## Current limitations

Cloud lighting and biome colour response are approximations. Biome atmosphere follows blended camera surroundings rather than per-pixel biome IDs. Water uses a planar mirror and screen-space refraction, so newly revealed and off-screen detail cannot always be reconstructed. Fine cloud and foliage detail can shimmer in motion. Nether, End and third-party resource packs have not received a complete visual review.

No Minecraft game assets, Complementary shader source, worlds, personal settings, logs or executable files are included.

**Keywords:** minecraft · horizon · shaderpack · wgsl · volumetric-clouds · water-rendering · atmospheric-scattering · god-rays · real-time-rendering
