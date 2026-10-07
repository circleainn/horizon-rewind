# Horizon Rewind 0.1.7

Experimental update by circleainn for BeamNG.drive 0.39.4.0.

- Added verified Grime 2.2 compatibility for recorded dirt/mud and window film.
  Grime 2.0 remains supported. Unknown versions and incompatible state layouts
  still leave the adapter inactive.
- Confirmed clean preview, dirty cancellation and clean commit with Grime 2.2,
  plus atomic repainting of body, roughness and glass canvases.

If dirt disappears immediately after an in-game Grime update, fully exit BeamNG
and start it again. The observed live update left Grime scripts unavailable;
the same archive loaded correctly in a fresh session. Rewind compatibility does
not enable Grime paint automatically or bundle its files.

# Horizon Rewind 0.1.6

Experimental update by circleainn for BeamNG.drive 0.39.4.0.

- Added optional traffic recording limits: 2, 4, 8 or All active AI cars. Find
  **Nearby cars** in Options after enabling traffic rewind. All remains the default.
- Limited recording prefers nearby cars and keeps existing recorders when
  distances are similar, avoiding frequent history loss as cars move around.
- Changing the limit preserves player history and cars that remain selected.
  The setting is saved and locked during rewind and restoration.

Unrecorded cars stay at their current positions during rewind and may be in your
path on release. Lower limits bound how many traffic cars are recorded/restored;
they do not guarantee a particular frame rate.

# Horizon Rewind 0.1.5

Experimental update by circleainn for BeamNG.drive 0.39.4.0.

- Releasing rewind no longer dispatches an extra catch-up seek after a delayed
  vehicle response. The preview already in flight completes before restoration.
- Impact release chooses the nearest complete recorded frame instead of always
  choosing the earlier one. This halves the maximum time adjustment across a
  fracture interval (normally 25 ms instead of 50 ms). Geometry, broken beams,
  mass, momentum and drivetrain state come from that same recorded frame.
- Reset/teleport boundaries keep their existing protection. Continuous movement
  still releases at its interpolated pose, and traffic still waits for the group
  before physics resumes.

Focused native fracture checks and the collision regression passed. This reduces
release jumps; it does not eliminate every adjustment or mesh-reconnection pop.

# Horizon Rewind 0.1.4

Experimental update by circleainn for BeamNG.drive 0.39.4.0.

- Fixed Grime's clear-then-delayed-redraw cycle during rewind. Each texture now
  receives a complete repaint in one browser task, with obsolete queued previews
  replaced by the latest snapshot. Unchanged appearance skips repainting.
- Restored smooth visual interpolation across broken-beam changes. Version 0.1.3
  held the earlier frame at these boundaries, making impact deformation skip.
  Release still selects a complete physical sample at a fracture boundary; this
  can cause a small position/shape adjustment when releasing during the impact.
- A slow traffic vehicle no longer stalls the player's preview. Each traffic
  recorder keeps one pending seek and the latest desired cursor. The group still
  synchronizes before physics resumes, with per-vehicle timeout protection.
- Hidden traffic before its recorded arrival no longer repeats geometry work.

Checks cover atomic repainting in all four installed Grime canvases, traffic
delays during preview, preview/cancel/commit and collision restoration. These
do not guarantee smooth frame rates on every vehicle, traffic count or system.

# Horizon Rewind 0.1.3

Experimental update by circleainn for BeamNG.drive 0.39.4.0.

- Newly spawned/recycled stock traffic no longer truncates your rewind window.
  Cars absent at the chosen time disappear and return to their traffic pool on
  release. Same-vehicle traffic repairs retain older history. Custom/manual AI
  outside the stock pool still uses the shortest shared history.
- Prevented interpolation across resets, large teleports and changes in broken
  beams, avoiding inconsistent geometry at those transitions.
- Reapplying the current traffic setting no longer restarts traffic recording.
- Added automatic Grime 2.0 compatibility for panel dirt/mud and window film.
  Requires Grime paint and its own canvas. Rebuilt patterns/colors are approximate;
  separate window splashes and burn marks are not rewound. No Grime files are changed.
- Replaced the silent emitter path with directly controlled UI audio. Original
  cue variants provide pitch changes for every rewind speed.

A native two-car collision check restored both cars without new broken beams,
and verified that late traffic preserves history and returns to its pool. Grime
preview/cancel/commit and canvas checks passed. These checks use no rendered
driving or audible output; damage restoration remains experimental.

Download **horizon_rewind_circleainn.zip** and keep only one installed copy.

# Horizon Rewind 0.1.2

Experimental update by circleainn for BeamNG.drive 0.39.4.0.

- Added **Options** with saved 20/40/60-second history. The default remains 20 seconds.
- Added **Rewind active traffic**, off by default. Active AI cars record their physical
  state and resume together. More cars add memory and recording/restore work.
- Traffic uses the shortest shared history; newly spawned, reset or recycled cars
  limit the available window. Deleted cars are not recreated. AI replans after
  release; police pursuits, traffic lights and other world systems are not rewound.
- Added an original speed-sensitive rewind sound effect and a mute option. Actual
  recorded engine/crash audio is not played backward.
- Optional particle/fluid histories use the selected duration with their existing
  memory budgets; dense effects may retain less history than the vehicles.

Damage restoration remains experimental. Native tire smoke, dirt/grass particles,
native airborne glass and skid marks are still unfinished. Dynamic Damage
Particles' Lua-owned flying glass remains supported.

Download **horizon_rewind_circleainn.zip**, then place it in your BeamNG user
folder's `mods` directory, keeping only one installed copy.

# Horizon Rewind 0.1.1

Experimental update by circleainn for BeamNG.drive 0.39.4.0.

- Replaced the native speed dropdown with an in-app menu.
- Added persistent minimize/hide controls and a restore tab.
- Recorded stock damage-material changes so supported glass damage follows rewind.
- Added DCT shaft/clutch state restoration and a safe in-gear handoff for stock
  shift controllers in Arcade and Realistic. Mid-shift animations are not exact.

Tire smoke, surface dust, grass effects, airborne stock glass and skid marks are
still outside the supported visual rewind. Their native engine state is not
exposed through the inspected mod APIs; this update does not claim to reverse it.

Hold your Recover Vehicle control to visibly rewind your car, then release to
resume driving. History records automatically in singleplayer Freeroam, with
up to 20 seconds available. An optional UI app provides Cancel and saved rewind
speed settings from 0.25× to 8×.

Includes supported damage and panel-latch restoration, wheel interpolation,
camera preservation, momentum handoff, and automatic compatibility with the
documented tire, particle and fluid mods. Optional mods are not required.

This is an experimental build. Damage visuals can pop on release, unsupported
mechanical state may reset, and stock particles and traffic do not rewind.
See the README for compatibility details before using it.

Download **horizon_rewind_circleainn.zip** below. Put it directly in your BeamNG user
folder's `mods` directory, keeping only one installed copy. GitHub's automatic
"Source code" archives are for development and are not installable mod packages.

The code is source-available under the included personal-use license. Reuploads,
sales and reuse in other distributed mods require permission, subject to the
license's platform and legal exceptions.
