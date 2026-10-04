# Horizon Rewind — prototype 0.1.1

## 0.1.1 update

The speed selector now uses an HTML menu inside the app, avoiding native select
popups. Minimize and hide modes persist locally and leave a restore control.
The browser regression checks all six speeds at 320/360-pixel widths, keyboard
selection, outside/Escape dismissal, persistence and releasing a held UI rewind
when hiding the panel.

The material adapter snapshots stock damage-switch slots, applies them during
preview, and restores their bookkeeping after repair. A native Covet regression
verified intact preview, cancellation to damaged glass and commitment to intact
glass. This tests material switching, not the rendering of flying shards or
historical broken mesh topology.

DCT recording now includes both shafts' gear indices, ratios and clutch state.
The stock shift-controller adapter restores accessible clutch/shaft tables and
returns to the in-gear callback. BeamNG blocks private scalar upvalue writes, so
pending shift targets are not written and an in-progress shift is not resumed
with reset targets. No sandbox restrictions are bypassed. Arcade and Realistic
Scintilla driving checks passed, including the recorded second-shaft selection,
momentum, held throttle and normal post-crash braking on a new impact. This is
not an exact replay of every intermediate shift state or every custom gearbox.

The 109 core checks and seven native latch assertions also passed. Native smoke,
surface particles and skid marks remain unimplemented; see [effects scope](EFFECTS_SCOPE.md).

Additional checks:

```powershell
./tests/run_glass_smoke.ps1
./tests/run_drive_smoke.ps1 -Model scintilla -Behavior arcade
./tests/run_drive_smoke.ps1 -Model scintilla -Behavior realistic
```

`node tests/ui_spec.cjs` needs Playwright, Edge and the installed game's Angular
runtime. Set `PLAYWRIGHT_MODULE` to a Playwright module path if it is not locally
installed, and `BEAMNG_ROOT` if the game is in a different location.

## Original architecture and verification

A player-car rewind mod for BeamNG.drive, built against the installed **0.39.4.0** Lua APIs. History builds automatically while you drive in singleplayer Freeroam. Hold your usual vehicle recovery control to watch your car move backward through its recent path, then release to continue driving with historical momentum.

## Use it

1. Put `dist/horizon_rewind_circleainn.zip` in the active BeamNG **user folder's `mods` directory**. The launcher has a **Manage User Folder → Open in Explorer** option. Do not put it in the Steam installation or unzip it inside another folder.
2. Start **singleplayer Freeroam** and drive for a few seconds. The mod keeps your recent history automatically.
3. **Tap your usual Recover Vehicle control** for stock vehicle recovery.
4. **Hold that same control for about 0.7 seconds** to start rewinding. Keep holding to move farther back, then release to resume driving.

No recording switch, new binding, or UI app is required. The mod adds the hold-to-rewind behavior to the existing recovery control while it is loaded; it does not edit the game's installed files or your saved bindings.

Vehicle Selector replacements, configuration reloads, and switching between spawned cars automatically attach rewind to the current vehicle and start a fresh history. This also handles replacements that reuse the same internal object ID. Geometry comes from each vehicle's own nodes, beams, and wheel definitions; no model-specific setup is required.

The optional **Horizon Rewind — Prototype** app in the UI Apps editor shows available history and provides a mouse-operated rewind button, **Cancel**, and a labeled **Speed** selector: **0.25×, 0.5×, 1×, 2×, 4×, or 8×**. Speed applies to the keyboard recovery control too and is saved in the user folder's `settings/horizonRewind.json`. Hold the app's rewind button and release to drive; press **Escape** while holding that button to cancel. Cancel returns to where that rewind began.

BeamNG's saved-replay feature remains separate and unaffected. Live rewind is unavailable while normal replay recording or playback is active.

## What this version does

- Automatically keeps up to 20 seconds of actual player-vehicle samples in memory, at up to 20 samples per simulation second.
- Interpolates node geometry during rewind, including rotation, body deformation and nodes belonging to detached parts.
- Interpolates both rim and tire-tread rotation instead of pulling rotating nodes through the wheel center. Each ring uses its recorded center, axis and node velocities, including multiple revolutions between samples. Detached tires follow their own moving center; recorded deformation remains part of the preview.
- On release, resets the structural baseline and reapplies the selected historical node positions, node masses, beam rest lengths, broken beams and deformation tracking.
- Sets the selected vehicle's translation velocity directly before unpausing, then applies one physics-step correction per node for rotation, wheel spin and fragment motion. This avoids turning the restored road speed into an apparent impact that triggers automatic post-crash braking.
- Restores available controller/gear state, selected powertrain angular speeds, hydraulics and supported fuel/battery energy.
- Records local door, hood, and trunk latch connections and restores the historical connections after the structural reset. Historically open panels remain open; cancelling preserves the live broken/open state. This uses vehicle controller/node definitions, without a model list. External trailer couplers are outside the player-car scope.
- Restores the exact interpolated preview position on release. Before structural repair, establishes the chosen pose as the engine's recovery baseline, keeping its temporary reset display at that position. Geometry is reapplied after the complete native reset callback, with current steering, pedals and smoothing preserved. Reset-generated parking-brake input is discarded; newer timestamped driver input takes precedence. Supported actual transmission ratios are restored without an extra shift from the reset ratio.
- Drops the abandoned future after resuming, and starts a new timeline from that point.
- Temporarily pauses the simulation during rewind; restores the pause state that existed before rewinding.
- Preserves the current camera mode, look direction, and zoom through rewind's structural reset. Physics resumes after the restored position has reached the game/display layer, preventing the temporary reset pose from entering camera smoothing.
- Clears history after a vehicle reset or vehicle change, and attempts cancellation before switching away during rewind.

## Prototype limits

**This is not yet a complete Forza-quality visual damage rewind.** Node geometry moves backward while held, but broken mesh connections, hidden/detached props and other damage visuals are rebuilt on release. Those transitions may pop. Release uses the exact interpolated node pose and velocity; discrete controller and damage topology state uses the preceding recorded sample.

Stock engine particles, skid marks, sound playback, traffic, missions, timers, AI decisions and the rest of the world do not rewind. Supported effect mods are covered separately below. Other vehicles remain at their current positions while the simulation is paused. Use open space for initial testing.

Thermal state, all mechanical failures, tire pressure, every controller's private data and third-party vehicle behavior are not fully snapshotted. A reset may repair unsupported subsystems, including when cancelling. This is intended for single-player Freeroam experimentation, not career, missions, competitive timing or multiplayer. Exact engine determinism is not claimed.

History lives only in RAM. It is discarded on disable, reset, vehicle change, level change or Lua reload. The buffer uses compact numeric arrays but very complex vehicles still cost memory and recording time.

Missing or failing optional controller, drivetrain, and energy-storage callbacks are skipped so custom systems do not stop structural rewind. Their private state may not be restored. A structural error stops rewind for that vehicle until it is reset or replaced; it does not disable rewind for other cars. Generic support does not guarantee compatibility with every third-party vehicle or recovery/camera mod.

## Optional effect compatibility

**Detachable Tires 1.2** (runtime `0.5.3.0.41.81`) is detected automatically. Its added inner mesh rings receive their own rotation interpolation, including when they slip relative to the tread after deflation. Rewind records supported detachment stages, replacement-mesh visibility, helper-beam support, tire pressure and collision state. Cancelling preserves a historically loose tire; committing before detachment restores the attached tire. The integration uses exact wheel/node ownership metadata, including separate coaxial tires, without a vehicle-name list.

**Tire Impact Punctures 1.4** is also detected. The adapter restores supported pressure, puncture and contact-detector state alongside Detachable Tires. Unknown versions/layouts keep their normal behavior rather than receiving speculative state edits. Tire collision changes use the installed mod's own safe post-reset settle window.

**Dynamic Damage Particles 2.0** is detected automatically. Its player-owned Lua debris and sparks have a bounded 10 Hz history with interpolated motion during rewind. Pieces disappear when rewinding before their creation, and recorded older pieces can return. Cancelling restores the live pieces; committing drops the abandoned future. Other vehicles' debris remains separate. Fresh crash emissions are suppressed while applying historical damage, preventing duplicate fragments. This covers this mod's Lua-rendered pieces, not stock engine particles.

**Fluid Spill Mod 1.3.0** is detected automatically. Rewind samples its puddles, smears, trails, streams, droplets, splashes, absorbent patches, and grains at 5 Hz. Cancelling restores the live fluid snapshot; committing drops the abandoned fluid future. The vehicle adapter also restores supported reservoir, burst, tank-flag, and slickness tables and suppresses fresh emissions during restoration.

Fluid Spill merges fluid without preserving its originating vehicle, so this integration rewinds its **singleplayer world fluid state**, including fluid left by other vehicles. It disables itself when Fluid Spill reports multiplayer active. Protected scalar fuel counters, damage-detection flags, and cosmetic animation timers are not rewound. These are sampled visual/state snapshots, not a reverse fluid simulation.

Compatibility uses the installed mods' existing Lua tables after version/layout checks. No third-party files are edited or redistributed; no Lua sandbox restrictions are bypassed. Unknown layouts stay inactive. Effect history is bounded separately from car history and can be shorter in dense scenes. Optional effect failures do not disable car rewind.

## Development and verification

All shipped code is original; installed game source was used as an API reference. No proprietary game assets or source files are included.

Build a correctly rooted mod archive with:

```powershell
./build.ps1
```

Run native physics checks (the game must be installed):

```powershell
./tests/run_specs.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_vehicle_engine_spec.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_wheel_engine_spec.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_closure_engine_spec.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_fluid_specs.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_particles_specs.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_tire_state_spec.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_tire_smoke.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_drive_smoke.ps1 -Model bastion -WithDirt
./tests/run_drive_smoke.ps1 -Model bastion -Coast
./tests/run_drive_smoke.ps1 -Model scintilla
./tests/run_fleet_smoke.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
./tests/run_effects_smoke.ps1 -GameRoot 'C:\Steam\steamapps\common\BeamNG.drive'
```

The engine suite uses the installed console physics engine and a stock D-Series to verify backward movement, reset/restore handoff, momentum, cancellation, historical broken beams, beam rest lengths and fuel. It does not edit the installation. The generated runner is retained locally and excluded from Git.

The Lua specifications cover bounded history, irregular frame timing, branching, pause ownership, automatic activation, native recovery tap/hold behavior, late callbacks, replay conflicts, timeouts, vehicle changes, reversible recovery hooks, wheel interpolation, camera lifecycle, and optional vehicle systems. These include mock engine objects and do not substitute for the native physics checks.

`tests/horizonRewindSmoke.lua` is a real game-engine smoke driver for an isolated test user folder. It is never included in the released ZIP. UI JavaScript/JSON and pointer/keyboard lifecycle behavior have also been checked with the installed Angular runtime. A rendered driving session is still needed to assess camera motion, sound, damage appearance and behavior across vehicles.

Validation on 2026-10-04: all **109 core specifications** passed (10 history, 46 coordinator, 11 recovery, 21 wheel interpolation, 11 camera, and 10 optional-system/handoff cases), plus **12 Fluid Spill and 13 particle compatibility checks** using the installed mods' Lua source. The native vehicle-engine suite passed all six restore flows covering geometry, momentum, damage, abort, unload, immediate re-enable, and intentional error recovery. Wheel geometry checks passed on pickup, Sunburst, city bus, and rock bouncer topology, including both rim and tread rings and multiple turns between samples. Additional numeric cases cover independent helper-ring rotation, free-tire translation/tilt, deformation, and coaxial tire ownership.

The full game completed **11 lifecycle scenarios** across pickup, ETK 800, Covet, Scintilla, city bus, and Wigeon: selector replacement, a Covet with broken door/hood/tailgate latches, same-model replacement, vehicle Lua reload, a newly spawned vehicle, and switching back to an existing vehicle. Every case automatically rebuilt history, rewound using the stock recovery callbacks, published the final position before unpausing, and resumed within a velocity-based movement bound. Every release frame was monitored: none jumped to the reset/spawn position; the largest movement from the last displayed preview while handling release was 0.041 m. Orbit, chase, and driver cameras retained their selected mode with zero reset calls; orbit look/zoom were preserved. These were numerical engine checks with rendering disabled; they do not establish visual perfection or universal third-party compatibility.

The native Covet latch regression passed seven assertions over three restores: previously closed latches reattached on the first physics step, deliberately open panels stayed open, and cancellation preserved broken latches. Physical panel positions matched the recorded closed pose within 0.000011 m. A separate detached-cluster probe confirmed that GE publication also updates detached panel nodes.

An engine-powered driving regression reproduced the earlier resume-stop bug on a stock Bastion: force-based speed restoration triggered its post-crash brake, cut the held throttle and stopped the car. The direct velocity handoff preserves recorded speed and live controls, including coasting; Bastion and Scintilla tests also confirm a new deceleration impact still activates the factory post-crash brake. Dirt-mod appearance is a separate investigation: Grime 2.0's replacement paint omits the stock paint palette and uses a fixed clean roughness of 38/255, so it does not preserve the original paint finish. This rewind update does not change those material definitions.

Ten focused tire-state checks cover optional-mod absence, version/schema checks, immutable snapshots, detachment stages, puncture history, external resets, consecutive restores, callback ownership and deferred collision updates. Native tests with both installed tire mods cover pickup 16-ray and T-Series 20-ray layouts, including real added helper nodes, healthy rewind, cancellation back to a detached tire, and committing before detachment. Measurements compare preview geometry against the actual surrounding recorded frames; already-recorded damage and tire/support separation are preserved. Attachment, mesh selection, pressure and collision bookkeeping are checked again after the mod's reset settle window. These checks run without rendering; an in-game driving session is still needed to assess appearance.

The full game also ran both installed effect mods together. Future fluid marks and debris disappeared during rewind, expired sparks returned, cancelling restored the original fluid and particle populations, committing removed future births, and an unrelated vehicle's debris object remained intact. A damaged-car particle check confirmed restored broken beams do not emit duplicate crash effects, while a genuinely new break after resume still does.

Relevant references: [BeamNG programming](https://documentation.beamng.com/modding/programming/), [extensions](https://documentation.beamng.com/modding/programming/extensions/), [custom input actions](https://documentation.beamng.com/modding/input/actions/), [replay](https://documentation.beamng.com/getting_started/replay/).

## Remove it

Close the game and remove this mod's ZIP from the user mods directory. The existing recovery control returns to stock behavior. No core replay files or saved user key bindings are changed by installation.
