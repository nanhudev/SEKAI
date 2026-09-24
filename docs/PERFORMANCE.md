# MVP 0.2 / 0.3 performance notes

## Actual visible sample

2026-09-24, in-app browser at 1292 × 910, gameplay in Mistvale during a two-second sample: 71.3 FPS, 14.0 ms/frame, 407 draw calls, 41,838 triangles. The values were read from the renderer's live counters. This is one scene sample, not a stable benchmark.

After the vegetation grouping and instancing pass, a village gameplay frame at the same browser size reported 86.0 FPS, 254 draw calls, and 47,898 triangles. Camera position and scene loading differ from the earlier sample, so the numbers show current behavior rather than a controlled improvement percentage.

## Required benchmark still outstanding

The 1920 × 1080 Low / Medium / High matrix has not yet been measured. Browser viewport control did not change the rendered surface during the earlier attempt. Memory was not available from the current browser instrumentation. Do not treat the sample above as proof of 1080p performance.

## Build information

`npm run build` passes with four MP3 tracks, title key art, and the Mistvale building kit. Vite warns that the main JS chunk exceeds 500 kB before compression; the current production file is 631 kB, 169 kB gzip. Future visual assets should use reusable modules, distance culling, modest shadow sizes and explicit LODs.
