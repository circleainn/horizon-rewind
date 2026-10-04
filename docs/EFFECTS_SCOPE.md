# Native effects rewind investigation

Requested scope: player-car tire smoke, dirt/dust clouds, grass and other surface
particles, native airborne glass, and skid marks. Rewind should remove future births,
restore past effects, and support cancellation without disturbing other vehicles.

## Findings in BeamNG 0.39.4.0 / Enhanced Vehicle Effects 1.7

Enhanced Vehicle Effects emits tire smoke with the vehicle's native
`addParticleVelWidthTypeCount` and `addParticleByNodesRelative` calls. Dirt,
gravel, mud, sand and grass use the same native emission interface. Its Lua
tables track emission cooldowns and smoke-interaction zones, not the rendered
particles' individual positions, ages or identities. The mod's reset clears
those zone/cooldown tables. Rewinding only those tables would not rewind smoke.

The inspected particle editor APIs operate on emitter/appearance datablocks;
they do not expose a snapshot/seek interface for the live vehicle particle pool.
The inspected skid-mark Lua interface controls whether a ground material permits
marks. It does not expose per-vehicle segment history or deletion. These findings
do not prove that no engine-side solution could exist, but there is no verified
API here suitable for shipping native effects rewind.

Re-emitting particles at historical wheel positions would play new effects
forward. Clearing all effects or globally disabling ground-model skid marks would
also affect other cars. Neither approach satisfies the requested behavior.

## Remaining implementation

A controllable replacement renderer or an engine API for owned particle/mark
state is needed. A replacement must record deterministic births, positions,
lifetimes and seeds during forward driving, support bounded history and arbitrary
time sampling, and integrate with the native effects without duplicate clouds or
skid marks. Smoke needs textured, depth-correct billboards; marks need persistent,
surface-aligned segments. Appearance, transparency sorting and performance require
rendered validation before enabling it by default.

This renderer is not implemented in 0.1.1. Existing Dynamic Damage Particles
compatibility works because that mod retains its own Lua particle state. This
already includes its flying glass shards (glass kind 3, plus its other supported
debris kinds); it is not part of the unfinished native-particle work. Glass
material switches are also controllable and are included in 0.1.1, independently
of airborne shards or broken flex-mesh connections.
