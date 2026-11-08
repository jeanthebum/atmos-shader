# Atmos Shader

**Warm daylight. Living skies. Water with depth.**

Atmos Shader is an original WGSL shader pack for Horizon, the Rust Minecraft client. It focuses on sunlit landscapes, volumetric clouds, reflective water and atmosphere that changes with the biome.

**Version:** 0.15.2 · **Shader API:** custom Horizon 0.2 · **Status:** experimental

## Runtime requirement

This version depends on a **custom Horizon renderer**. Stock Horizon does not currently provide all of the extensions this pack uses. It is not an Iris or OptiFine shader pack.

Required extensions include the expanded Frame uniform layout, reflection-depth and opaque-scene bindings, procedural water-droplet geometry, and native performance-profile bundles. The compatible renderer uses Horizon base commit `fd06d1c2650b52d8d4bb3d808ca73e55971ba717` with local renderer changes and `HORIZON_HDR_FRAME=float`.

This repository contains the shader sources and their procedural data textures for review. Renderer binaries and the renderer patch are not included here. A compatible renderer is required to run or fully validate the shader.

## Features

- **Daylight:** warm directional sunlight, cool skylight, Lambertian diffuse lighting, foliage transmission and filtered shadows.
- **Living skies:** a round sun, volumetric cumulus clouds, atmospheric haze and shadowed god rays.
- **Water:** procedural waves, Fresnel reflections, planar terrain mirrors, depth absorption, refraction, shallow-water clarity and golden sunset highlights.
- **Vegetation:** animated leaves, grass and flowers with anchored roots.
- **Biome atmosphere:** humid jungles, misty swamps, cool deep forests, desert heat shimmer, bright snow and subtle cherry-biome colour shifts. Biome light tint can be disabled independently.
- **Rain and leaf drips:** procedural liquid shading, curved normals, refraction, sun highlights and impact rings, using geometry supplied by the custom renderer.
- **Finishing:** internal HDR lighting, bloom, ACES-style tonemapping, optional exposure adaptation and a configurable camera filter. Final output is SDR.

## Performance profiles

Select **Shader packs → General → Performance profile** in the compatible client.

| Profile | Main settings |
| --- | --- |
| **potato** | Sunlight and animated vegetation; volumetric clouds, mapped shadows, mirrors, shafts, bloom and canopy beads disabled. |
| **medium** | 1024 shadows at 96 blocks, Low clouds and lighter biome/weather effects. |
| **high** | 2048 shadows at 128 blocks, Fast clouds and shafts, terrain reflections. |
| **ultra** | 4096 shadows at 192 blocks, High clouds and shafts, reflected clouds and full biome atmosphere. |
| **rich kid** | 8192 shadows at 256 blocks, Cinematic clouds and 128-sample god rays. |

**Custom** preserves manual quality settings. Profiles leave exposure, sunlight colour, camera filter, biome tint and wind controls intact. The default is Ultra; High offers a more moderate GPU budget. Actual performance depends on resolution, scene, render distance and hardware.

## Source layout

The `shaders/` directory is the complete pack: **17 WGSL files, one manifest and two required procedural PNG textures**.

| Files | Purpose |
| --- | --- |
| `horizon-shaders.toml` | Stages, textures, material tags, settings pages and performance presets |
| `palette.wgsl`, `environment.wgsl` | Lighting palette and biome/weather response |
| `sky.wgsl`, `density.wgsl` | Sky and cloud-density model |
| `material.wgsl`, `vertex.wgsl` | Terrain/foliage lighting and vegetation motion |
| `water.wgsl`, `weather.wgsl` | Water optics, rain and liquid droplet shading |
| `post/` | Clouds, reconstruction, god rays, heat shimmer, bloom, grading and edge smoothing |
| `tonemap.wgsl` | Final display transform |
| `cloud-volume.png`, `density-noise.png` | Procedural rendering data; required, not showcase images |

The manifest retains the internal ID `afterglow_hdr` for compatibility with earlier saved settings and the custom renderer's droplet integration. The public name is **Atmos Shader**.

## Validate and package

With the compatible custom `horizon-shader` tool available:

```sh
horizon-shader check shaders
horizon-shader pack shaders --out Atmos-Shader-0.15.2.hshader
```

Install the resulting `.hshader` through the compatible Horizon client's shader-pack menu. Package only `shaders/`; repository documentation and Git files do not belong inside the pack.

Version 0.15.2 passed native validation for all 13 stages, structural checks for all 20 pack files and live native-menu checks for the five presets. It is a rename of the tested 0.15.1 shader with unchanged rendering algorithms and texture data. No new benchmark is claimed for this release.

## Current limitations

Cloud lighting and biome colour response are approximations. Biome atmosphere follows blended camera surroundings rather than per-pixel biome IDs. Water uses a planar mirror and screen-space refraction, so newly revealed and off-screen detail cannot always be reconstructed. Fine cloud and foliage detail can shimmer in motion. Nether, End and third-party resource packs have not received a complete visual review.

No Minecraft game assets, Complementary shader source, worlds, personal settings, logs or executable files are included.

**Keywords:** minecraft · horizon · shaderpack · wgsl · volumetric-clouds · water-rendering · atmospheric-scattering · god-rays · real-time-rendering
