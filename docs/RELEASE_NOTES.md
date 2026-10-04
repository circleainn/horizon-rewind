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
