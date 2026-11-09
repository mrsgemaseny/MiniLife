# MiniLife: plains soundscape

Original music composed and synthesized in Chat GPT session No. 2 on 2026-11-04.
These are original Minecraft-inspired pieces, not recordings from Minecraft.

Included compositions: Endless Sun, Glass Orbit, Moon Tide, Sand Circles,
Under the Ice, Copper Rain, Distant Shore, After the World.
Glass Orbit uses the version without the upper melodic layers; the final struck
chord is removed and the last twelve seconds fade out. The rejected Dk Dk
experiments are deliberately absent from this directory and every playlist.

Nature sounds are offline synthesized assets, not field recordings: soft wind,
three distant bird phrases, two cricket phrases and one grasshopper phrase.
They are scheduled independently of music with long randomized pauses.

The whole current local map uses plains acoustics. Individual mixed biome tiles
do not switch tracks or ambience. Daytime birds disappear at night; insects become
more frequent after 17:00. Rain and interiors suppress new nature calls. Wind is
attenuated indoors. Music is lowered during combat; new songs wait for peace.
Pause freezes playback and timers. Music is selected without immediate repeats,
with 90–210 seconds of nature alone after each track.

Audio buses: Music -> Master; Ambience -> SFX -> Master. Existing Music and Effects
sliders control these layers. Nature does not share the gameplay SFX voice pool.
Music stays at its authored pitch and ends naturally; it does not loop.

Rebuild compressed assets with Node.js and FFmpeg:

```
node tools/build_plains_audio.cjs <directory-containing-original-WAV-files>
```

Sources for this session's music are preserved in `tools/audio_sources/`.
Run `compose.cjs`, `glass-orbit.cjs`, `glass-orbit-low.cjs`, `five-orbits.cjs`,
`emptiness.cjs`, and `endless-sun.cjs` there to regenerate the source WAV files.
Use that directory as the input to the build command above.
