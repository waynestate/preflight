# PREFLIGHT brand files

**The mark is a runway threshold seen from the cockpit:** the striped "piano key" markings every aircraft crosses
before takeoff, with a gold centreline running ahead. Every push crosses PREFLIGHT's checks before it reaches
production.

## Colours
| Role | Colour |
|---|---|
| Stripes, tile | Wayne State green `#0C5449` |
| Centreline dashes (the only gold) | Wayne State gold `#FFCC33` |
| Stripes on the tile or on dark backgrounds | White `#FFFFFF` |
| Site accent only, never in the mark | Deep blue `#0E5A7D` |

Gold never sits behind white text.

## Files
| File | Use |
|---|---|
| `preflight-mark.svg` | The mark on light backgrounds: green stripes, gold dashes |
| `preflight-mark-white.svg` | The mark on dark or green backgrounds: white stripes, gold dashes |
| `preflight-mark-mono.svg` | One colour (`currentColor`), for print and single-ink use |
| `preflight-tile.svg` | The app icon: a green rounded tile with the white runway |
| `preflight-favicon.svg` | The tile simplified for 32 and 64 px: three stripes and one dash |
| `preflight-favicon-16.svg` | Hand-hinted on the 16 px grid. One unit is one pixel |
| `preflight-avatar-512.png` | The GitLab project avatar and the Open Graph image base |
| `preflight-mark-1024.png`, `preflight-mark-white-1024.png` | Raster marks for slides and documents |
| `favicon-16.png`, `favicon-32.png`, `favicon-64.png`, `favicon.ico` | Browser favicons; the `.ico` holds all three |

## Geometry
The SVGs are drawn from exact geometry, not traced, so the shapes are symmetric to the hundredth of a unit.
- **The stripes:** five equal stripes, 352 units wide in total at the base line (y 400 on a 512 grid), with gaps
  0.34 of a stripe. They converge on a vanishing point at (256, 128) and are cut level at y 236.
- **The dashes:** two centreline dashes taper with a gentler perspective, so the far one stays visible.

## Rendering
The PNGs were rendered with Inkscape 1.4, for example
`inkscape preflight-tile.svg --export-type=png --export-filename=preflight-avatar-512.png -w 512 -h 512`. The `.ico`
was built with ImageMagick 7: `magick favicon-16.png favicon-32.png favicon-64.png favicon.ico`.
