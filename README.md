# mpv-object-audio

> **Part of the [Software Defined Home Theatre](https://github.com/praveenchandrahas/Software-Defined-Home-Theatre) project.** The main repository holds the documentation, build log, results and the installer checks; this is one of its parts. Sibling repositories: [linux-theater-dsp](https://github.com/praveenchandrahas/linux-theater-dsp) · [seekthumbs](https://github.com/praveenchandrahas/seekthumbs) · [theater-measurement](https://github.com/praveenchandrahas/theater-measurement).

An installer and wrapper that gives a Linux machine a self-contained **live Dolby Atmos / DTS:X player**: the Omniphony object renderer, the harletty-bridge decoders and a patched mpv,
installed in their own folder and started as the `mpv-object-audio` command, with a video configuration tuned for a 1080p projector (VAAPI, gpu-next on Vulkan, BT.709/BT.1886,
60 nit target peak, bt.2390 tone mapping, mitchell downscaling, deband).

```bash
git clone https://github.com/praveenchandrahas/mpv-object-audio && cd mpv-object-audio
./scripts/object-audio-install.sh deps      # prints one apt line (mpv's build dependencies); run what it prints
./scripts/object-audio-install.sh           # engine and bridges: prebuilt releases; mpv-omniphony has no releases, so mpv is built from source (minutes)
mpv-object-audio film.mkv                   # or right-click a film in Dolphin -> mpv-object-audio
```

Files: `scripts/object-audio-install.sh` (install, update, status, remove, deps), `scripts/mpv-object-audio` (the wrapper; `--oa-info`, `--oa-check`), `scripts/mpv-atmos` and
`scripts/mpv-atmos-overlay-off.lua` (the earlier wrapper of the author's rig, kept for comparison), `docs/omniphony-debugging.md` (how the stack was built and debugged).

It works alone. Optionally it calls `eq ensure` / `eq prepare FILE` from [linux-theater-dsp](https://github.com/praveenchandrahas/linux-theater-dsp) before playback (skipped when `eq` is not installed, or with `OBJECT_AUDIO_DSP=0`),
and [seekthumbs](https://github.com/praveenchandrahas/seekthumbs) can add seek-bar thumbnails.

## How the installer works

`scripts/object-audio-install.sh` installs the latest engine and bridges as **prebuilt releases** (`liborender-<tag>-linux-x86_64.zip` from mgth/Omniphony, `harletty-bridge-<tag>-linux-x86_64.zip` from harletty/harletty-bridge) and builds **only mpv-omniphony from source**, because it publishes no releases (main of mgth/mpv-omniphony, which pins the mpv fork tag: mpv 0.41.x plus the `ad_orender` patches; the build needs no engine). Everything goes into `~/.local/opt/mpv-object-audio`, and the installer refuses to install the command unless the new mpv loads the engine. It is **independent of `mpv-atmos`**: separate mpv binary, engine and bridges, and its own mpv config folder `~/.config/mpv-object-audio` (a one-time copy of `~/.config/mpv`: keys, uosc, the overlay script). The wrapper `scripts/mpv-object-audio` carries the same video settings as `mpv-atmos` (VAAPI, gpu-next on Vulkan, BT.709/BT.1886, peak 60, bt.2390, mitchell with linear downscaling, debanding, 512 MiB demuxer cache).

```bash
scripts/object-audio-install.sh deps      # prints the apt line (mpv's build dependencies)
scripts/object-audio-install.sh           # install or update (a re-run takes the latest releases)
scripts/object-audio-install.sh status
scripts/object-audio-install.sh remove
```

Entry points: `mpv-object-audio FILE` in a terminal; Dolphin right-click submenu "mpv-object-audio" (play, fullscreen, play with log in Konsole, show streams); "Open with" in any KDE file dialog. It is not made the default handler. The DSP hooks (`eq ensure`, `eq prepare`) and the IPC socket are shared with `mpv-atmos` on purpose, so the router and the automatic profile switching work unchanged; `OBJECT_AUDIO_DSP=0` turns them off. The bridge pairing: the latest engine and the latest bridge release should match (the bridge notes say which Omniphony they require); pin with `OA_OMNIPHONY_TAG` / `OA_BRIDGE_TAG` if they do not.

**Run on the rig 2026-10-25** (laptop away from the DAC): the asset names matched, the build finished, the engine (v0.7.0, ABI 0.12) and the three bridges (v0.9.0, bridge_api 0.6.0, Omniphony 55af2c5) loaded, and an Atmos TrueHD clip and a DTS:X clip played with sound. Not yet checked with the DAC: routing through CamillaDSP (`preflight playing`) and the level against `mpv-atmos` (`preflight compare FILE`: the new engine logs a -8 dB dialogue normalisation on the Atmos clip). The engine config `~/.config/omniphony/config.yaml` is shared with `mpv-atmos`, so layout and render settings are common to both players. The installed router was updated the same day with `install-autoroute.sh` (it was older than the repository's and lacked `eq prepare`). The download step needs GitHub's API, which a rate limit can refuse: set `GITHUB_TOKEN`.

## Credits

The hard part, decoding and rendering Atmos objects live on Linux, is the work of others:
**[Omniphony](https://github.com/mgth/Omniphony)** and **[mpv-omniphony](https://github.com/mgth/mpv-omniphony)** by mgth (the renderer and the mpv integration),
**[harletty-bridge](https://github.com/harletty/harletty-bridge)** by harletty (the decoder plugins), and **[truehdd](https://github.com/truehdd/truehdd)** by Rainbaby (the TrueHD decoder that harletty's decoder is a fork of).
This repository only installs them and wraps mpv; their licences apply to what they provide and are not summarised here.

## Third-party licences

The installer downloads other projects; they keep their own licences (this repository contains none of their code, and its Apache-2.0 licence does not change theirs):

| Component | Licence (as stated by the project; check the version you install) |
|---|---|
| [Omniphony](https://github.com/mgth/Omniphony) engine | GPL-3.0-or-later (its README); decoder bridges are loaded at run time and "may be licensed separately" |
| [harletty-bridge](https://github.com/harletty/harletty-bridge) | not checked here: see its LICENSE |
| [mpv-omniphony](https://github.com/mgth/mpv-omniphony) | not checked here: an mpv fork, so GPL/LGPL-family; see its LICENSE |
| [truehdd](https://github.com/truehdd/truehdd) (the decoder harletty's is a fork of) | Apache-2.0 |
| [mpv](https://mpv.io) | GPL-2.0-or-later by default, LGPL-2.1-or-later when built that way (mpv's documentation) |

## Adapting it to your system

Paths and user names in the docs and in `scripts/mpv-atmos` are from the author's machine, and the video settings in the wrapper target a 1080p projector (60 nit peak, BT.1886).
Change them for your display and install folder (`OA_HOME`).

## Licence

[Apache License 2.0](LICENSE) (see also [NOTICE](NOTICE)). Dolby, Dolby Atmos, DTS and DTS:X are trademarks of their owners; this project is not affiliated with or endorsed by them. It contains no media files and no decoder code.

Part of the [software-defined home theatre](https://github.com/praveenchandrahas/Software-Defined-Home-Theatre) project.

## On-screen status and controls (theater_status.lua)

`scripts/theater_status.lua` adds an overlay to mpv: **F9** toggles a status panel (source, route, profile, engine, CamillaDSP load, clipping and
underruns) and **F10** opens a control menu (EQ on/off, profile mode, upmix flavours, adaptive engine). It runs the `eq` command, so the router stays the only
thing that changes the audio; with `theater-ctld` running (linux-theater-dsp) the panel also shows the live DSP numbers, otherwise it uses `eq status --json`.
With uosc installed the menu is uosc's (mouse and keyboard); otherwise a built-in menu is drawn (arrow keys, Enter, Esc, mouse wheel and click). Changes that
cost about a second of silence, and `eq off`, always ask for a second confirmation, because mpv is playing whenever the menu is open.

Install: `./scripts/install-theater-status.sh` (copies the script into `~/.config/mpv` and `~/.config/mpv-object-audio`; `--bindings` also adds the two keys
to each `input.conf`; `remove` undoes both). Options in `script-opts/theater_status.conf`: `eq`, `ctl_url`, `menu=auto|uosc|builtin`, `refresh`.
Tested under a mocked mpv API only (`tests/test_theater_status.py`, needs `pip install lupa`); how it looks and behaves in the real player is unverified.
