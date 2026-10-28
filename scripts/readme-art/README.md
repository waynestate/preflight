# PREFLIGHT README art kit

Regenerates every image under `docs/readme/` from this repo's own front page (`site/`), its CI
templates (`templates/<name>/template.yml`) and its brand files (`site/brand/`). Nothing is drawn
by hand: the hero and the gallery are screenshots of the real page, the checklist card is built
from the page's own checklist and annunciator panel plus the job names and timeouts in the
templates, the cast is the stack's marks resized, and the badges read their facts from
`composer.json`.

## Run

The same three commands in either shell:

| Windows PowerShell | macOS / Linux sh |
|---|---|
| `npm --prefix scripts/readme-art ci` | `npm --prefix scripts/readme-art ci` |
| `npx --prefix scripts/readme-art playwright install chromium` | `npx --prefix scripts/readme-art playwright install chromium` |
| `node scripts/readme-art/build.mjs` | `node scripts/readme-art/build.mjs` |

Every path resolves from the script's own location, so it runs from any folder. The page opens as
a `file://` URL: no server, no network. Requests for anything that is not a local file are
aborted.

## What it makes

- `docs/readme/hero.jpg`: the front page's hero, with the sticky header and the two lines that
  name the deploy platform hidden.
- `docs/readme/checklist.svg`: the before-takeoff checklist, ticked item by item while the
  annunciator lamps go green. Under `prefers-reduced-motion` it shows the finished card.
- `docs/readme/gallery.jpg`: a contact sheet of three existing mobile crops from
  `site/screenshots/sections/` (placards, flight plan, flight manual).
- `docs/readme/board.jpg`: the brand board, re-encoded.
- `docs/readme/cast/*.png`: one 96×96 mark per stack part, WayneUI on its green tile.
- `docs/readme/badges/*.svg`: `php`, `licence` and `components`, made locally by `badge-maker`.

The build exits 1 if any file grows past 300 KB, or if captured text names an internal host.
Same inputs, same outputs.

If the checklist ever shows a red lamp, the art is fine. Go and fix the pipeline.
