# Asset provenance

## Original source

`neon-city-source.png` is the original 1586×992 RGB image generated with the
OpenAI Media Service on 2026-08-24. It contains an embedded C2PA 2.2 manifest,
including an `OpenAI Media Service` signer identity and a `c2pa.created` action.
Its C2PA claim identifier is:

```text
urn:c2pa:7b440e57-37b1-49b7-8429-248b959e33e1
```

Generation brief: a wide 16:10 cyberpunk megacity at midnight, viewed down a
rain-soaked elevated avenue; deep central vanishing point; dark readable upper
center; neon magenta, cyan, and violet lighting; wet reflective pavement,
mist, holographic geometry, and no people, logos, readable words, watermark, or
UI.

The embedded C2PA manifest records origin and processing assertions. It is not
a copyright license. Keep this private repository private unless the owner has
chosen an explicit distribution license.

## Derived assets

- `backgrounds/neon-city-poster.jpg` — 1920×1200 static desktop/lock poster.
- `preview.png` — 720×450 theme preview.
- `preview-unlock.png` — 720×450 lock preview.
- `unlock.png` — 1920×1200 lock-compatible image.
- `assets/neon-city-loop.mp4` — silent H.264, 960×600, 6 fps, 12-second loop.

The derived files were produced locally from `neon-city-source.png` with image
and video tooling. Re-encoding does not preserve the source PNG's embedded C2PA
manifest; provenance is maintained by this document and `ASSETS.sha256`.

## Integrity

Run:

```bash
sha256sum -c ASSETS.sha256
```

The source and all shipped derivatives are covered by that checksum manifest.
