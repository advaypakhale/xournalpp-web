# xournalpp-web

Run Xournal++ in a container and draw in it from a browser with a pressure
sensitive pen.

The container starts a headless X server (`xf86-video-dummy`), Xournal++ from
the [advaypakhale/xournalpp](https://github.com/advaypakhale/xournalpp) fork,
and [Weylus](https://github.com/H-M-H/Weylus). Weylus serves a page that
streams the screen as H.264 and sends the browser's pointer events back; on the
server it turns them into a uinput tablet with pressure and tilt, which the X
server reads like any other tablet. Encoding is software only, so no GPU is
needed. arm64 only for now.

## Run

```sh
docker run -d --name xournalpp \
  --device /dev/uinput \
  -v /dev/input:/dev/input \
  --device-cgroup-rule 'c 13:* rmw' \
  -v xournalpp-data:/data \
  -p 127.0.0.1:1701:1701 \
  ghcr.io/advaypakhale/xournalpp-web:latest
```

Open `http://<host>:1701`, tick "uinput" and "stylus input", then connect.
Chromium reports pen pressure from Wacom devices on Linux; Firefox has not
always.

| variable | default | |
|---|---|---|
| `WEYLUS_ACCESS_CODE` | unset | if set, the page asks for it before connecting |
| `SCREEN` | `1920x1080` | size of the virtual screen |
| `XOURNALPP_FILE` | unset | file under `/data/notes` to open at start |

`/data/notes` holds the documents, `/data/config` the Xournal++ settings.
Files in a directory mounted at `/seed` (`settings.xml`, `toolbar.ini`,
`palette.gpl`, ...) are copied into `/data/config/xournalpp` at start when
not already there. Xournal++ rewrites `settings.xml` itself, so the seed is
never linked; delete a file under `/data/config/xournalpp` and restart to take
the seed's version again.

The pen device is created through `/dev/uinput` and its event node appears in
the host's `/dev/input`, which is why that directory is bind mounted and the
cgroup rule for major 13 is needed. Everything in the container runs as root:
Xorg wants it, and the container has nothing else in it.

## How the pieces fit

Weylus creates its uinput devices when a browser connects, but an X server
without udev only opens the devices named in its config at startup.
`weylus/0001-precreate-uinput.patch` adds `--precreate-uinput`, which creates
one set of devices at startup and shares them between clients. The entrypoint
waits for those devices, writes their event nodes into `xorg.conf`, and only
then starts Xorg. The X input driver is `evdev` rather than `libinput`,
because libinput rejects devices without udev's `ID_INPUT_*` properties.

`weylus/0002-ffmpeg6-buffersink.patch` lets Weylus build against Ubuntu
24.04's FFmpeg 6.1; upstream targets 7.1.

`matchbox-window-manager` runs so that Xournal++ can maximise; without a
window manager GTK leaves the window at its default size.

## Build

`Dockerfile` pins the Xournal++ and Weylus commits as build args; bump them
there. CI builds on push to `main` and publishes
`ghcr.io/advaypakhale/xournalpp-web:<commit>` and `:latest`.
