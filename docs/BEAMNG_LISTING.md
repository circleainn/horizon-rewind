# Horizon Rewind

**Author:** circleainn  
**Version:** 0.1.2 — experimental

**Tagline:** Hold recovery to rewind your car. Release to drive again.  
**Upload:** `horizon_rewind_circleainn.zip` from the GitHub release, not GitHub's source-code ZIP.

Horizon Rewind keeps a short history of your car while you drive in singleplayer
Freeroam. Hold your existing **Recover Vehicle** control to watch the car rewind,
then release when you want to take over again. Tapping the control still performs
normal recovery.

## How to use

Install the ZIP in your BeamNG user folder's `mods` directory, or use the repository
Install button once this resource is approved. Keep only one copy installed.
Start Freeroam and drive for a few seconds. Hold your Recover Vehicle binding
for about 0.7 seconds to rewind; release to resume.

The optional **Horizon Rewind — Prototype** UI app provides a rewind button,
Cancel, and a speed selector from 0.25× to 8×. Your speed setting is saved and
also applies to keyboard controls. You do not need the app or a recording switch
to use rewind.

The panel can be minimized or hidden behind a small restore tab. Its speed
choices open inside the app, without a native browser dropdown.

## Features

- 20 seconds of history by default, with optional 40/60-second buffers.
- Optional rewind for active AI traffic cars; the group shares the shortest available history.
- A speed-sensitive rewind sound effect with a mute option; this is not reversed game audio.
- Visible backward motion, wheel rotation and recorded body deformation.
- Restoration of supported damage, panel latches, motion and drivetrain state.
- Historical glass/damage material switches during preview; airborne glass is separate.
- Arcade and Realistic gear restoration, including both shafts of supported DCTs.
- Automatic setup when changing cars; no individual vehicle configuration.
- Automatic optional support for Detachable Tires 1.2, Tire Impact Punctures 1.4,
  Dynamic Damage Particles 2.0 and Fluid Spill Mod 1.3.0.

These optional mods are not included or required. Compatibility is limited to
supported versions and data layouts. Fluid Spill compatibility rewinds its world
fluid state, including fluid left by other vehicles.

## Before downloading

This is an experimental release tested against BeamNG.drive 0.39.4.0.
It is intended for singleplayer Freeroam, not career, missions or multiplayer.
Custom vehicles and other recovery mods may behave differently.

Damage visuals can pop as connections and props are rebuilt when you release
rewind. Some mechanical, thermal and controller state is not recorded and may
be repaired by the reset used during restoration. Stock particles,
Enhanced Vehicle Effects particles, skid marks and other world systems do not
rewind. Traffic rewind is optional and uses the shortest shared history; AI routes
are replanned, and deleted cars are not recreated. BeamNG's saved replay feature remains separate; live rewind is unavailable
while replay recording or playback is active.

History clears when you reset or change cars. Highly complex vehicles and dense
effect scenes use more memory and processing time. See the GitHub documentation
for detailed compatibility limits.

## Downloads and support

Project: https://github.com/circleainn/horizon-rewind  
Downloads: https://github.com/circleainn/horizon-rewind/releases  
Bug reports: https://github.com/circleainn/horizon-rewind/issues

For a bug report, include your BeamNG version, vehicle/configuration, other active
mods, what happened, and steps to reproduce it. Check logs for personal details
before uploading them.

## Permissions

Free to download and play. Private edits are allowed. Reuploads, sales and reuse
of the code or assets in other distributed mods require circleainn's written permission,
subject to the full license and applicable platform terms. Gameplay videos,
screenshots and streams are welcome, including monetized ones.

Source-available under the Horizon Rewind Personal Use License. Not affiliated
with BeamNG GmbH, Microsoft, Playground Games or Turn 10 Studios.

---

## Submission notes — omit this section from the public overview

Choose the appropriate gameplay/utility category in the current upload form.
Use version 0.1.2 and keep the ZIP filename unchanged for future updates.
Add at least two real in-game images showing the car during rewind and the
optional controls; a short gameplay clip would also help demonstrate the feature.
Do not present a mockup as a gameplay screenshot. Capture these after a rendered
driving check. Moderator review determines acceptance.
