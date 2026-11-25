# QA report (13 Nov 2026, fourth pass: presentation audit)

Written by the implementation session. This is not an independent review.

## Commands and results

| Command | Result |
|---|---|
| `npm run validate:data` | PASS: 34 components, 26 edges, 6 scenarios, 12 events, 13 evidence refs |
| `npm run build` (validate + strict `tsc --noEmit` + `vite build`) | PASS; JS 581 kB (153 kB gzip), CSS 9 kB, fonts bundled; no CDN |
| `npm test` (Playwright 1.49, Chromium headless shell 131, software GL, 1440 x 900, 1 worker) | **20 passed** (one of them only writes screenshots) |
| `npm run build:single` | PASS: one 737 kB HTML file; opened from `file://` with WebGL, 0 console errors, 0 network requests |
| `npm run manifest` | 17 evidence files hashed (SHA-256), 2 entries are patterns or out-of-tree runs |

| Test | Checks |
|---|---|
| loads | No console or page errors, no request to any external host; scope line and playback-mode label visible |
| routes | `#how`, `#architecture`, `#results`, `#scope` render; `#explore/access/endp` survives a reload |
| block list | Search, Tab, Enter selects a block; inspector shows name, 5,807 LUT, status badges; URL updates |
| scenario state | Authorization, UART and LED derive from events: correct after GRANT and again after seeking back |
| scrub bar, keyboard orbit | Scrubbing to the end, the start and the middle gives the matching event and outputs; arrow key on the 3D view moves the camera |
| 3D picking | 25 rays at 5 poses return the expected block; a real mouse click selects the RoT verifier; draw calls <= 250, triangles <= 250,000 |
| camera-pose matrix | 13 poses: +Y, -Y, +Z, -Z, +X, -X, four corner obliques, network, tile 3, underside. Every ray aimed at a block lands on a named component; 42 exact-hit assertions for unobstructed blocks |
| camera controls | Step buttons, view menu, logical-view toggle work without dragging |
| phone (390 px) | No horizontal scroll; controls at least 24 px tall |
| accessibility (axe-core 4.10, WCAG 2.0 / 2.1 / 2.2 A and AA rules) | 0 violations on each of the 5 sections |
| public-safe | `dist/` has no local path, image hash, demo key, dev metadata or CDN host |
| How it works animation | Steps, gate open / closed, memory cells `C0 DE 5A 5A`, UART `T3 PASS` / `T0 REFUSED`, tile 0's packet stays inside its tile, stepping back restores the earlier state |
| screenshot grid | 14 camera poses, 5 pages, 1 phone view, 1 single-file view in `qa/screens/` |

## Facts re-derived from RTL in this pass

32-bit flits, 3 virtual channels with 4-flit buffers and their roles (`rtl/dual_lane/NOC_PKG.sv` 50-57, 164-168); 128-bit tag (same file, 86);
80-bit epoch, 64-bit sequence number, replay rejection (`noc_l2_auth_p7_i9.sv` 25, 74-75, 285); 224-bit challenge and GRANT / REVOKE sent as
packets on the same channel and path (`pq_rot_verifier.sv` 39, 53-56).
Still from the owner's fact list only: the 512-bit response payload split (measurement + tag).

## Not done, or not possible in this session

| Item | Status |
|---|---|
| Frame rate on a real GPU, load time, mobile performance | **Not measured.** Tests use software rendering |
| Firefox and Safari | **Not tested** (only Chromium installed) |
| Screenshot pixel-diff baselines | **Not set**; they need a real-GPU reference machine |
| Screen-reader pass | **Not done.** axe checks rules, not the listening experience |
| Human look at the 3D from every side | Screenshots reviewed by the builder (home, tile 3, back, underside, three animation steps). Labels overlap at grazing side angles |
| Behaviour inside the hosted link | **Not checked.** The single file was tested from disk; the hosted page's sandbox was not exercised |
| Usability trial with 2 to 3 people | **PENDING** |
| Independent review | **PENDING**; needs a separate session |
| Verified-trace playback, stalls and credit waits | Not built (decision D5): no cycle-stamped trace exists |
| Typed port lists per block | Board-top pins only; other blocks show their RTL instance path |
| Before / after image comparison | Not produced; the corrections are listed below |

## Fourth pass (13 Nov): presentation audit P1 / P2 items

| Audit item | Change | Test |
|---|---|---|
| P-01 opening view | Two-line summary, "Watch the demo" button, tile buttons above the 3D view | Watch the demo test |
| P-02 tile inspection | Tile card for every tile: name, purpose, LUT / FF / BRAM of the main block, what it does, role in the current scenario, parts list; unmeasured values read "Not separately measured" | Tile card test (all six tiles) |
| P-03 unimplemented features | Header line is now a positive tagline; one short scope line in the opening view; limits in a collapsible section and on the Scope page | Routes test |
| P-04 WebGL fallback | Without WebGL the stage shows the step-by-step diagram (2D animation) | Not run: the test browser has WebGL |
| P-06 one guided demo | "Watch the demo" plays all six scenarios in order; the tile card and highlight follow whoever acts | Watch the demo test |
| P-07 plain language | Every step has who / what / why in plain words; routes, channels and protocol fields moved to "Technical detail" | Captions checked in the demo test |
| P-08 results | Four key figures first, then what works, cost of security, board status; full evidence collapsible | Routes test |
| P-09 small targets | Inline links are now at least 32 px tall | axe scans |
| P-10 / P-11 animation wording | Explicit controls on the diagram; it is described as a conceptual, RTL-informed animation | How it works test |
| P-05 real-GPU checks | **Still open**: needs a person on a GPU-equipped browser | none |

## Third pass (13 Nov): realism and the How it works animation

- Every block is now drawn as a surface-mount part: routers and logic as QFN and gull-wing packages with tin leads, the three security blocks as ceramic packages with gold lids and castellated pads, the CPU tiles as small modules carrying their four sub-blocks, the shared memory as a TSOP, the SPOOF port as a pin header, the empty tile as an unpopulated footprint. Laser-style markings on each part.
- Package and board: rounded substrate, underfill fillet, silicon die with standard-cell texture, die- and board-side capacitors and resistors, flattened solder balls, solder mask with traces, vias and silkscreen, metal-lid oscillator, tactile buttons, slide switch, LEDs with lenses, a studio environment for reflections and a shadow-catching floor.
- Board LEDs follow the design (board top RTL lines 122-126): LD0 tile 3 authorized, LD2 CPU A pass flag, LD3 heartbeat (bit 24 of the 50 MHz counter, about 0.34 s per half period), RGB = CPU B refused flag.
- How it works page: a ten-step animation (click or Play) showing the measurement, challenge, response, grant, write, read-back, local refusal, revoke and the simulation-only forged packet on a flat tile view, with UART text, LEDs and button 2.

## Corrections against the earlier chip view

- After REVOKE the refusal is at tile 3's own bridge (RTL), not at the tile-2 memory front end.
- The forged-packet step is labelled simulation only; the SPOOF port is tied off in the board image.
- Every block area comes from the 12 Nov report (the old view mixed in 7 Nov figures).
- Virtual channels are told apart by shape and line pattern; the palette has three hue families only.
- three.js and fonts are bundled; nothing loads from a CDN.

## Verdicts (builder's own; to be replaced by the independent review)

| Gate | Verdict | Condition |
|---|---|---|
| Technical claims | CONDITIONAL GO | RTL sign-off audit still open; response payload split not re-derived |
| Routing and interaction | CONDITIONAL GO | Explanatory mode only; routes validated against the mesh graph and the XY rule |
| 360-degree model | CONDITIONAL GO | 13-pose ray matrix passes; no human all-angle review |
| Browser and accessibility | CONDITIONAL GO | axe clean in Chromium; other browsers, screen reader and real-GPU numbers missing |
| Static public release | CONDITIONAL GO | Self-contained and public-safe; usability trial and independent review pending |
