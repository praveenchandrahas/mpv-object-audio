# mpv-object-audio

Part of the [Software Defined Home Theatre](https://github.com/praveenchandrahas/Software-Defined-Home-Theatre) project.

An installer and wrapper that gives a Linux machine a self-contained **live Dolby Atmos / DTS:X player**: the Omniphony
object renderer, the harletty-bridge decoders and a patched mpv, installed in their own folder and started as the
`mpv-object-audio` command, with a video configuration tuned for a 1080p projector (VAAPI, gpu-next on Vulkan,
BT.709/BT.1886, 60 nit target peak, bt.2390 tone mapping, mitchell downscaling, deband).

The hard part — decoding and rendering Atmos objects live on Linux — is the work of others: **[Omniphony](https://github.com/mgth/Omniphony)**
and **[mpv-omniphony](https://github.com/mgth/mpv-omniphony)** by mgth, **[harletty-bridge](https://github.com/harletty/harletty-bridge)**
by harletty, and **[truehdd](https://github.com/truehdd/truehdd)** by Rainbaby. This repository only installs them and wraps mpv;
see the [README's credits](https://github.com/praveenchandrahas/mpv-object-audio#credits) and the third-party licence table in
[Install](install.md#third-party-licences) for what each project is and how it is licensed.

!!! warning "Pre-release, experimental"
    Written with an AI assistant; checked against simulated rooms and REW exports; used and checked by the author in his
    own room (one room, one author). No external or second-person validation yet. The packages are unsigned.

Start with [Install](install.md) to get the player on your machine, then [Usage](usage.md) to run it. The
[build & debugging log](omniphony-debugging.md) records, problem by problem, how the underlying mpv-omniphony stack was
brought up on the author's own Kubuntu 24.04 machine — useful background if you hit something similar, not a polished guide.
