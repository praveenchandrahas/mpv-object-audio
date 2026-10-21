# mpv-omniphony: build and debugging log

How the live Atmos decoder and renderer was brought up on Kubuntu 24.04, problem by problem. Compiled from the
conversations of July to September 2026. Dates are those of the conversations; version numbers are as reported in them.
Each entry says what was seen, what the cause was, and how it was confirmed. The stack is the work of other people
(see the credits in the [README](../README.md#credits)); this log only records what happened on this machine.

## Stack and what each part does

| Part | Role |
|------|------|
| [mpv-omniphony](https://github.com/mgth/mpv-omniphony) | mpv patched with an `ad_orender` audio decoder; patches are applied to a pinned mpv (here v0.41.0, 24 patches) |
| [Omniphony](https://github.com/mgth/Omniphony) | The renderer (`liborender`, VBAP gains for any speaker layout, OSC control) and Omniphony Studio (3D view, layout management) |
| [harletty-bridge](https://github.com/harletty/harletty-bridge) | A runtime-loaded decoder plugin (`libharletty_bridge.so`) that turns TrueHD and E-AC-3 Atmos into PCM plus object metadata. Its README says the `harletty` decoder it wraps is a fork of [truehdd](https://github.com/truehdd/truehdd) by Rainbaby, and that the repository also carries DTS and DTS:X input |

`liborender` is loaded at run time (dlopen), so a self-built mpv works with an engine installed by Studio.
Bridge and engine must agree on the `bridge_api` minor version: Omniphony v0.6.0 expects bridges built against 0.4.x,
and v0.5.x expects 0.3.x (Oct 2026 conversation). Check this before updating either side.

## Problems and fixes

### 1. The prebuilt Linux mpv-omniphony 0.4.2 binary could not play anything (Aug 2026)
- **Seen:** no sound and no usable video. `./mpv --ao=help` listed only `null` and `pcm`; `--vo=help` listed renderers but no
  window backends.
- **Cause:** the release asset was built without PipeWire, ALSA, X11 or Wayland development packages, most likely on a
  minimal CI runner. This was inferred from the backend lists, not confirmed with `ldd`.
- **Fix:** build from source with the desktop dev packages installed.
  ```sh
  sudo apt build-dep mpv
  sudo apt install libpipewire-0.3-dev libasound2-dev libx11-dev libwayland-dev \
    libwayland-egl-backend-dev libegl1-mesa-dev meson ninja-build git
  git clone https://github.com/mgth/mpv-omniphony.git && cd mpv-omniphony
  scripts/apply-patches.sh v0.41.0
  cd build/mpv-v0.41.0 && meson setup _b -Dorender=enabled && meson compile -C _b
  ./_b/mpv --ao=help        # must list pipewire, alsa, pulse
  ```
- **Confirmed:** `--ao=help` then listed `pipewire`, `pulse`, `alsa`, `jack`, `sndio`. A GitHub issue was filed upstream.
- **Gotchas met on the way:** the first meson run failed and `rm -rf _b` was needed before retrying; `_b` lives under
  `build/mpv-v0.41.0/`, not in the repository root; the "Falling back to direct application" lines during patching are
  fuzz matching and harmless.

### 2. First live run (10 Aug 2026)
Working command: `./_b/mpv --ad=orender --ad-orender-osc --ad-orender-library=... --ad-orender-bridge-path=... --hwdec=vaapi FILE`.
Omniphony Studio showed 16 live object trails, LFE routed direct, and mpv reported
`AO: [pipewire] 48000Hz 8ch float`. In the Amaze demo almost all channels are objects (1 routed entry, 15 trailing object channels), which is expected for that trailer.
- **Not yet true at that point:** the renderer was using its stock room geometry, not the owner's room, and the output stream
  had no semantic channel names (`unknown8`), so anything downstream has to route by port index. The project has done so since.
- `--ad-orender-osc` turned out to enable the Open Sound Control link used by Studio. It does not control the on-video overlay.

### 3. Trajectory overlay would not stay off (Sep 2026)
- **Seen:** the overlay is always on by default; the only controls are runtime toggles (`script-binding omniphony_overlay/toggle`
  and related messages), and there is no launch flag to switch it off.
- **First attempt:** a Lua script that sends the toggle on `file-loaded`.
- **Bug:** the script was both auto-loaded from `~/.config/mpv/scripts/` and passed with `--script=`, so it ran twice and
  the two toggles cancelled. Fix: load it from one place only.
- **Limitation:** a toggle is not an explicit "off"; if the engine's default ever changes, the script would turn it on.

### 4. Virtual bed layouts not found (Aug to Sep 2026)
- **Seen:** `WARN orender_engine::virtual_bed: Virtual bed layout '5.1.yaml' not found on disk, using built-in fallback positions`, same for `7.1.yaml`.
- **Cause:** a packaging path mismatch. The files shipped under `/usr/lib/Omniphony Studio/layouts/legacy/` while
  `liborender.so.0` searched `/usr/share/orender/layouts/legacy/`.
- **Outcome:** reported as a GitHub issue; accepted and merged upstream, per the conversation.

### 5. mpv option errors (Jul to Sep 2026)
`--tone-mapping-mode=hybrid` was removed from current mpv and made the player exit at start-up ("option not found"). It was deleted from the wrapper and every other option was validated against the option parser.
Note that tone-mapping options only act on HDR sources; a 1080p SDR test file showed them loaded but idle.

### 6. Height channels silent with offline Cavernize files (21 Jul 2026)
Before Omniphony, rendered 5.1.2 files lost their height channels. mpv negotiated a plain 7.1 layout with the ALSA sink,
which has no meaning for top-back channels, so ffmpeg silently dropped channels 7 and 8. An index-based
`lavfi=[channelmap=map=0|1|2|3|6|7|4|5:channel_layout=7.1]` fixed it, verified by rendering mpv's PCM to a file and
measuring per-channel peaks. The live Omniphony path outputs 8 channels directly.

### 7. Dolby Vision check (Sep 2026)
Stock mpv logged no `dovi` or `rpu` lines, which proved nothing because the log vocabulary was assumed. The decisive check
was mpv's stats overlay showing `Colormatrix: dolbyvision`. The sample files are Profile 7.6 MEL, not FEL.

### 8. Haruna integration (unresolved)
Haruna with a custom `libmpv.so` and `LD_LIBRARY_PATH` did not engage `orender`. Cause never found; `mpv-atmos` is used instead.

## Lessons
- Check `--ao=help` and `--vo=help` first when a custom mpv is silent. It separates "the build is wrong" from "the config is wrong".
- Do not trust a log search term you have not seen succeed. Go one level lower (here, the stats overlay or `ffprobe` side data).
- Pin the engine and bridge together by `bridge_api` minor version.
- DTS and DTS:X support is separate and newer than the Dolby path. Release notes for harletty reported 16-bit DTS-HD MA playing about 48 dB too quiet until a fix in v0.7.1, so treat DTS as less proven than TrueHD.
