# Usage

## Running it

```bash
mpv-object-audio film.mkv
```

or right-click a film in Dolphin and choose **mpv-object-audio**.

Entry points: `mpv-object-audio FILE` in a terminal; the Dolphin right-click submenu "mpv-object-audio" (play,
fullscreen, play with log in Konsole, show streams); "Open with" in any KDE file dialog. It is not made the default
handler.

## Wrapper flags

The `mpv-object-audio` wrapper (`scripts/mpv-object-audio`) itself takes:

```bash
mpv-object-audio FILE...        # play
mpv-object-audio --oa-info      # show what it would run and whether the bridges load
mpv-object-audio --oa-check     # play a test tone through the engine and show the engine/bridge log lines
```

Any other arguments are passed straight through to the underlying mpv.

## Environment variables

| Variable | Effect |
|---|---|
| `OA_HOME` | Install folder (default `~/.local/opt/mpv-object-audio`). |
| `OBJECT_AUDIO_DSP=0` | Skip the `eq ensure` / `eq prepare FILE` CamillaDSP profile-switching hooks before playback. |
| `OA_OMNIPHONY_TAG` / `OA_BRIDGE_TAG` | Pin the installer to a specific Omniphony engine / harletty-bridge release, if the latest of each do not agree with one another. |
| `GITHUB_TOKEN` | Used by the installer's download step, which calls GitHub's API and can otherwise be rate-limited. |
| `THEATER_MPV_SOCK` | Overrides the IPC socket path the wrapper passes to mpv (default `${XDG_RUNTIME_DIR:-/tmp}/theater-mpv.sock`). |

## What the wrapper sets up for you

`mpv-object-audio` is a separate player from `mpv-atmos`: its own mpv binary, engine and bridges, and its own mpv
config folder `~/.config/mpv-object-audio` (a one-time copy of `~/.config/mpv`: keys, uosc, the overlay script). It
carries a video configuration tuned for a 1080p projector (VAAPI hardware decoding, `gpu-next` on Vulkan,
BT.709/BT.1886, 60 nit target peak, bt.2390 tone mapping, mitchell downscaling with linear downscaling, debanding, a
512 MiB demuxer cache). The DSP hooks (`eq ensure`, `eq prepare`) and the IPC socket are shared with `mpv-atmos` on
purpose, so the router and automatic profile switching keep working across both players; `OBJECT_AUDIO_DSP=0` turns
them off.

See [Install](install.md#adapting-it-to-your-system) if you need to change the display target or install folder for
your own machine — the paths and video settings above are tuned for the author's own 1080p projector.

## On-screen status and controls

The status panel and controls for mpv (press **C**) moved to
[Roomtone](https://github.com/praveenchandrahas/Roomtone) (`overlay/`), next to the status page it shares its code
path with. Install it from there.

## Optional companions

Two small mpv add-ons are built to work next to this player; neither is needed for Atmos, and neither has yet been
confirmed in a real mpv session alongside it.

- **[seekthumbs](https://github.com/praveenchandrahas/seekthumbs)**: preview thumbnails on the seek bar for a film
  library. `./seekthumbs.py install-viewer` writes into `~/.config/mpv-object-audio` by default, so it reaches films
  started with `mpv-atmos`.
- **[mpv-shelf](https://github.com/praveenchandrahas/mpv-shelf)**: a poster browser for the same library (Ctrl+b). Its
  installer adds the script and the key to `~/.config/mpv`, and to `~/.config/mpv-object-audio` if that folder exists.
  It starts films by their real file path, so the codec-profile detection of the router (Atmos, DTS:X) and the
  wrapper's per-file handling are meant to keep working; whether they do when a film is started from the shelf has
  not been checked on the rig.
