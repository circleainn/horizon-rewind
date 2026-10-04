"""Generate the original looping rewind cue using only Python's standard library."""
import math
import random
import struct
import wave
from pathlib import Path

rate = 24000
duration = 4
rng = random.Random(712)
frames = []
low = 0.0
for i in range(rate * duration):
    t = i / rate
    low += 0.12 * (rng.uniform(-1, 1) - low)
    # Rising envelopes and descending chirps suggest tape winding backward.
    phase = (t * 4) % 1
    envelope = math.sin(math.pi * phase) ** 2 * (0.3 + 0.7 * phase)
    tone = math.sin(2 * math.pi * (180 * t + 8 * math.sin(2 * math.pi * t)))
    texture = low * (0.5 + 0.5 * envelope)
    frames.append(0.20 * tone * envelope + 0.32 * texture)
# Smooth the periodic noise seam without placing silence at every loop.
crossfade = int(rate * 0.03)
for i in range(crossfade):
    blend = i / crossfade
    frames[-crossfade + i] = frames[-crossfade + i] * (1-blend) + frames[i] * blend
frames = frames[crossfade:]
path = Path(__file__).resolve().parents[1] / 'mod/art/sound/horizonRewind/rewind.wav'
path.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(path), 'wb') as out:
    out.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    out.writeframes(b''.join(struct.pack('<h', round(v * 32767)) for v in frames))
print(path)

# The game's file-source API cannot change pitch after creation. Bake the
# supported playback speeds at a standard sample rate instead.
for speed, suffix in [(0.25, '025'), (0.5, '050'), (2, '200'), (4, '400'), (8, '800')]:
    pitch = max(0.5, min(2, speed ** 0.35))
    samples = []
    for i in range(int(len(frames) / pitch)):
        position = i * pitch
        left = int(position)
        fraction = position - left
        value = frames[left] * (1 - fraction) + frames[min(left + 1, len(frames) - 1)] * fraction
        samples.append(struct.pack('<h', round(value * 32767)))
    target = path.with_name(f'rewind_{suffix}.wav')
    with wave.open(str(target), 'wb') as out:
        out.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
        out.writeframes(b''.join(samples))
    print(target)
