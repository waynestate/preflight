# PREFLIGHT front page

A static page: `index.html`, `assets/preflight.css`, `assets/preflight.js`. No build step. Serve the `site/` folder
from anywhere (Citadel, any web server, or `python -m http.server` inside `site/` for a look; some browsers block
fonts over `file://`).

- type: **B612** 400/700 and **B612 Mono** 400/700 (SIL OFL 1.1, self-hosted in `assets/fonts/` from `@fontsource`,
  licence in `OFL-b612.txt`). B612 is the typeface Airbus commissioned for cockpit displays, so the placards and
  annunciators are set in the real thing. Lato from WayneUI for body text; the system monospace for code, because
  B612 Mono sets a full cell after every full stop and `0.1.0` would read as `0. 1. 0`.
- world: a flight deck on a cream chart page. A heading indicator with the mark at its hub, a laminated
  normal-procedures card, an annunciator panel, a taxi strip with gold hold-short lines, engraved component placards,
  a flight-plan form, flight-manual WARNING / CAUTION / NOTE boxes and a departures board. Green and gold are the
  family tie; deep blue `#0E5A7D` (the board's site-only accent) does the chart grid and the form rules.
- base: WayneUI 2.0.8, copied from its static path into `assets/wayne-ui/` (tokens, Lato, buttons, tabs, skip link,
  sr-only), then re-dressed in `assets/preflight.css`.
- magic: **the checklist runs itself as you scroll.** Each item on the card is a real PREFLIGHT job with its real
  command. As an item crosses the reading line it is ticked, its annunciator goes green and the aircraft on the taxi
  strip rolls past the next hold-short line (TEST, AUDIT, STYLE). The last item lights CLEARED FOR TAKEOFF and the
  aircraft rolls down runway Citadel and lifts off. **Run the checklist** plays it without scrolling. The guarded
  **Inject an advisory** switch (first press lifts the striped cover, second throws it) fails the Composer audit: the
  lamp goes red, a stop bar lights across the AUDIT line and the clearance becomes HOLD SHORT.
- hero: the compass card swings round and settles on the gold heading bug, the title's letters light like panel
  backlighting, and the PAPI lights settle from all red to two white, two red: on the glidepath.
- coming soon: the accessibility suite, a contract suite and site freshness sit on the panel as dim, hatched lamps
  and in "Deferred items"; none has a command, because none exists yet.
- marks: `brand/` is PREFLIGHT's (generated with ChatGPT, never redrawn). `assets/marks/` holds the other stack parts'
  marks, copied from the sibling sites; WayneUI uses its own reversed mark on green.
- reduced motion: the page is the finished flight, every word present at first paint: every box ticked, every lamp
  green, the aircraft lined up on the runway with its clearance. The buttons still work, instantly, and the status
  line says what happened.

Screenshots are in `screenshots/` (desktop 1440, mobile 390, reduced motion, a motion GIF, and per-section mobile
crops in `screenshots/sections/`).

V1, rotate. Please keep your tests green until the pipeline has come to a complete stop.

## Links between the stack sites

Links to the other parts are committed as production URLs (`https://<project>.apps.wayne.edu/`), so crawlers and
visitors without JavaScript always get production. `assets/stack-env.js` (the same file on every stack site) rewrites
them to `http://127.0.0.1:18432/<project>/site/` in development, for a static server whose root is the
folder that holds all the projects side by side. Dev is picked automatically on `localhost` or `127.0.0.1`; `?env=dev` or `?env=production` forces
one (remembered until `?env=auto`), `<meta name="stack-env">` sets the page default, and `?devBase=http://127.0.0.1:<port>`
points at a server on another port. WayneUI links stay on production.
