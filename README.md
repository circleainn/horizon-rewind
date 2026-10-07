# Horizon Rewind

**by circleainn · Experimental 0.1.7 · BeamNG.drive 0.39.4.0**

Hold your vehicle recovery control to rewind your car. Release to drive again.
Horizon Rewind records 20 seconds of player-car history automatically in singleplayer Freeroam. Longer history and traffic rewind are optional.

[Download](https://github.com/circleainn/horizon-rewind/releases) · [Report a bug](https://github.com/circleainn/horizon-rewind/issues)

## Install and use

1. Download **horizon_rewind_circleainn.zip** from Releases. GitHub's automatic “Source code” archives are not installable mod packages.
2. Put the ZIP in your BeamNG **user folder's `mods` directory**, keeping only one version installed. Do not extract it or put it in the Steam installation.
3. Start singleplayer Freeroam and drive for a few seconds.
4. Hold your existing **Recover Vehicle** control for about 0.7 seconds to rewind. Release to resume driving. Tapping the control still performs normal recovery.

No new binding or recording switch is required. Changing vehicles automatically starts a fresh history.

The optional **Horizon Rewind — Prototype** UI app provides a rewind button, Cancel and a saved speed selector: 0.25×, 0.5×, 1×, 2×, 4× or 8×. Speed also applies to the recovery control. Escape cancels while holding the app's button.

Click the speed button to open the in-app choices. Use **−** to minimize the panel
or **×** to hide it behind a small Rewind tab. Click **+** or the tab to restore
the panel. The view is remembered; keyboard recovery still works while hidden.

Open **Options** to select **20, 40 or 60 seconds**, enable **Rewind active traffic**,
or turn off the **rewind sound effect**. Settings are saved. Defaults are 20 seconds
and traffic off. Changing history length clears the buffer. History and traffic
settings cannot change during rewind.

With traffic enabled, **Nearby cars** can limit recording to **2, 4 or 8** active
AI cars. **All** is the default. Nearby cars are preferred, with some tolerance
to keep existing history when distances are similar. Changing the limit preserves
your car's history and the buffers of cars that remain selected. Unrecorded cars
stay at their current positions during rewind and may be in your path on release.

Traffic rewind records the physical state of currently active AI traffic cars,
including position, deformation, wheels and momentum, and resumes the group
together. Newly spawned or recycled stock traffic no longer shortens your car's
history. Rewinding past a car's recorded arrival hides it; releasing there returns
it to the traffic pool for a later safe spawn. Same-vehicle traffic repairs retain
their older history. Custom/manual AI outside the stock traffic pool still limits
rewind to shared history. Deleted cars are not recreated, and parked cars outside
the traffic AI system are not recorded.
Traffic AI replans from its restored pose; police pursuits, traffic lights and
other world logic are not rewound.

40 and 60 seconds retain roughly two and three times as many vehicle snapshots.
Traffic adds recording and restoration work for each car. Optional particle and
fluid histories follow the selected duration while keeping their existing memory
limits, so dense effects can retain less history than the vehicles.

The sound is an original looping rewind cue with pitch tied to rewind speed.
It fades out on release and at the end of the buffer. It is not a recording of
engine, tire or crash sounds playing backward.

To uninstall, close the game and remove the ZIP. Installation does not change game files or saved bindings.

## What to expect

Rewind follows recorded node positions, body deformation and wheel rotation. On release it restores supported damage, door/hood/trunk latches, momentum and drivetrain state while preserving current controls and the camera selection.

Crash deformation interpolates during preview. Releasing between samples with
different broken beams uses the nearest complete physical frame, which can cause
a small adjustment at the impact boundary. Traffic previews update independently
and synchronize before physics resumes.

Releasing finishes the preview already in flight without adding another
catch-up seek for accumulated input time.

Stock damage-material switches, including supported cracked and shattered glass
materials, now follow the preview timeline. Dynamic Damage Particles' flying
glass shards are covered by its existing integration. Native BeamNG glass
particles and broken mesh connections are separate and are not fully reversed
during preview.

Arcade and Realistic use the recorded gearbox state. Dual-clutch transmissions
also retain both shaft gears and clutch state. Pending shifts resume from the
recorded engaged gear instead of continuing a shift with reset controller targets;
this does not reproduce every fraction of a mid-shift transition.

This remains an experimental mod:

- Damage connections and props are rebuilt on release; some visual changes pop.
- Unsupported mechanical, thermal and custom controller state may reset.
- Stock particles, Enhanced Vehicle Effects particles, skid marks and other world systems do not rewind. Traffic vehicle rewind is optional and experimental.
- History clears after resets, vehicle changes and level changes. Complex vehicles and dense effect scenes cost more memory and processing time.
- Career, missions and multiplayer are outside this release's scope.
- BeamNG's saved replay feature is separate. Live rewind is unavailable during replay recording or playback.

Generic support does not guarantee every third-party vehicle or mod. Automated engine checks run without rendering; they do not establish visual perfection. See [development and validation](docs/DEVELOPMENT.md) for details.

## Optional compatibility

These integrations activate automatically for supported versions and data layouts. None is required or bundled.

| Mod | Supported behavior |
| --- | --- |
| Detachable Tires 1.2 | Recorded detachment state, mesh visibility and independent tire-ring motion |
| Tire Impact Punctures 1.4 | Supported pressure and puncture state |
| Dynamic Damage Particles 2.0 | Player-owned Lua debris, including flying glass shards, and sparks |
| Fluid Spill Mod 1.3.0 | Sampled fluid effects and supported reservoir state |
| Grime 2.0 / 2.2 | Recorded panel dirt/mud and window film with Grime paint selected |

Fluid Spill combines effects without retaining vehicle ownership, so its integration rewinds **world fluid state**, including fluid left by other cars. Unknown compatibility layouts remain inactive. Full limits are documented in the development notes.

Grime's textures are rebuilt from recorded buildup. Individual speckles and mixed
soil colors are approximate; separate window splashes and burn marks are not
rewound. Grime paint and its own texture canvas must be active. The integration
does not alter paint materials or require installing Grime.

If Grime stops appearing after an in-game repository update, fully exit BeamNG
and reopen it before troubleshooting the paint selection. A live update can leave
Grime's scripts unavailable for the rest of that session.

## Build

Run `./build.ps1` in PowerShell 7. The installable package is written to `dist/horizon_rewind_circleainn.zip`. It includes runtime files and the license, not tests or development notes. Test commands are in [DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Permissions

This project is **source-available**, under the [Horizon Rewind Personal Use License](LICENSE). You may play it, inspect the source and make private edits. Reuploads, sales and reuse in other distributed mods require circleainn's written permission, subject to the license's platform and legal exceptions. Gameplay videos and streams are welcome, including monetized content.

Not affiliated with BeamNG GmbH, Microsoft, Playground Games or Turn 10 Studios.
