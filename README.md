# Atmos Shader

**Warm daylight. Living skies. Water with depth.**

Atmos Shader is an original WGSL shader pack for Horizon, the Rust Minecraft client. It focuses on sunlit landscapes, volumetric clouds, reflective water and atmosphere that changes with the biome.

**Version:** 0.16.0 · **Shader API:** StratosAPI 0.1.x (Horizon 0.2) · **Status:** experimental

## Runtime requirement

Atmos now requires [StratosAPI](https://github.com/jeanthebum/stratos-api), a separately maintained Horizon native renderer mod. Install StratosAPI through the launcher's **Mods → Add from GitHub**, let it build the compatible instance, then restart and select Atmos. See the API repository for exact Horizon pins, installation steps and current limitations. This is not an Iris or OptiFine pack.

The manifest declares `[stratos] api = ">=0.1.0, <0.2.0"`. Atmos releases and public API versions are independent. Stratos rejects incompatible packs before GPU compilation and automatically selects the floating-point scene renderer; an HDR environment override is no longer needed.

This repository contains Atmos shader sources, required procedural textures, and its packaged shader release. StratosAPI's renderer code, tests and releases live in its own repository. Use the Stratos-built `horizon-shader` tool for validation and packaging.

## Download

Get [`Atmos-Shader-0.16.0.hshader`](releases/Atmos-Shader-0.16.0.hshader) and its [`SHA256SUMS`](releases/SHA256SUMS). Install StratosAPI first, import the `.hshader` into that instance, and select Atmos in Shader packs. WGSL compiles for your GPU at load time. The package contains no worlds, renderer binaries or development files.

## Features

- **Daylight:** warm directional sunlight, cool skylight, Lambertian diffuse lighting, foliage transmission and filtered shadows.
- **Living skies:** a round sun, volumetric cumulus clouds, atmospheric haze and shadowed god rays.
- **Water:** procedural waves, Fresnel reflections, planar terrain mirrors, depth absorption, refraction, shallow-water clarity and golden sunset highlights.
- **Vegetation:** animated leaves, grass and flowers with anchored roots.
- **Biome atmosphere:** humid jungles, misty swamps, cool deep forests, desert heat shimmer, bright snow and subtle cherry-biome colour shifts. Biome light tint can be disabled independently.
- **Rain and leaf drips:** procedural liquid shading, curved normals, refraction, sun highlights and impact rings, using geometry supplied by the custom renderer.
- **Finishing:** internal HDR lighting, bloom, ACES-style tonemapping, optional exposure adaptation and a configurable camera filter. Final output is SDR.

## Performance tuning

Tune shadow resolution and distance, cloud quality, reflections, god rays, bloom and biome effects individually in the pack settings. This keeps the pack compatible with Horizon's schema 1 manifest reader.

## Source layout

The `shaders/` directory is the complete pack: **17 WGSL files, one manifest and two required procedural PNG textures**.

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

The manifest retains the internal ID `afterglow_hdr` for compatibility with earlier saved settings. Droplet capabilities now come from the public StratosAPI declaration and option mapping. The public name is **Atmos Shader**.

## Validate and package

With the Stratos-built `horizon-shader` tool available:

```sh
horizon-shader check shaders
horizon-shader pack shaders --out Atmos-Shader-0.16.0.hshader
```

Install the resulting `.hshader` through the compatible Horizon client's shader-pack menu. Package only `shaders/`; repository documentation and Git files do not belong inside the pack.

The cloud volume uses a 71-cubed RGBA atlas to stay below Horizon's 1 MiB PNG upload limit; its four channels and wrapped slice gutters are retained. Performance settings are individual options because schema 1 does not define automatic multi-option profiles.

## Current limitations

Cloud lighting and biome colour response are approximations. Biome atmosphere follows blended camera surroundings rather than per-pixel biome IDs. Water uses a planar mirror and screen-space refraction, so newly revealed and off-screen detail cannot always be reconstructed. Fine cloud and foliage detail can shimmer in motion. Nether, End and third-party resource packs have not received a complete visual review.

No Minecraft game assets, Complementary shader source, worlds, personal settings, logs or executable files are included.

**Keywords:** minecraft · horizon · shaderpack · wgsl · volumetric-clouds · water-rendering · atmospheric-scattering · god-rays · real-time-rendering
