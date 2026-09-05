# xournalpp-web

Run Xournal++ in a container and draw in it from a browser with a pressure
sensitive pen.

The container starts a headless X server (`xf86-video-dummy`), Xournal++ from
the [advaypakhale/xournalpp](https://github.com/advaypakhale/xournalpp) fork,
and [Weylus](https://github.com/H-M-H/Weylus). Weylus serves a page that
streams the screen as H.264 and sends the browser's pointer events back; on the
server it turns them into a uinput tablet with pressure, which the X server
reads like any other tablet. Encoding is software only, so no GPU is
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

Open `http://<host>:1701`. Nothing has to be set first; the settings drawer is
behind the handle in the top right corner.

The browser has to support WebCodecs to decode the video: Chrome 94, Firefox
130 on desktop, or Safari 16.4 and later. Firefox on Android does not; there
the screen stays blank and the settings drawer's log says why. Chromium reports
pen pressure from Wacom devices on Linux; Firefox has not always.

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

Killing the container with unsaved work leaves an emergency save behind. The
entrypoint moves it to `/data/notes/recovered-<timestamp>.xopp` on the next
start, so it is opened like any other document instead of through Xournal++'s
restore dialog.

The pen device is created through `/dev/uinput` and its event node appears in
the host's `/dev/input`, which is why that directory is bind mounted and the
cgroup rule for major 13 is needed. Everything in the container runs as root:
Xorg wants it, and the container has nothing else in it.

## How the pieces fit

Both Weylus and Xournal++ are patched at build time, from `weylus/` and
`xournalpp/`.

Weylus creates its uinput devices when a browser connects, but an X server
without udev only opens the devices named in its config at startup. Weylus is
patched to create one set of devices at startup instead and share them between
clients. The entrypoint waits for those devices, writes their event nodes into
`xorg.conf`, and only then starts Xorg. The X input driver is `evdev` rather
than `libinput`, because libinput rejects devices without udev's `ID_INPUT_*`
properties.

The pen's barrel buttons go out on the same device as `BTN_STYLUS` and
`BTN_STYLUS2`, ahead of the tip's `BTN_TOUCH`, because Xournal++ picks the tool
for a whole stroke from the button state at the moment the tip goes down.

Video reaches the browser as bare H.264 Annex-B, one frame per websocket
message with the time it was captured. There is no MP4 container and no
`<video>` element, because a media element holds a reserve of decoded frames to
keep playback smooth and that reserve is the largest delay in the loop. The
page configures a WebCodecs `VideoDecoder` from the stream's own parameter sets
and paints each frame onto a canvas as it comes out.

Xournal++ writes its current tool, colour, thickness and zoom to a unix socket
whenever any of them change, and Weylus relays the lines to the browser without
reading them. The page draws the stroke it is sending onto a canvas over the
video, in the width and colour the real ink will have, so ink appears under the
pen without waiting for the round trip. It follows Xournal++'s pen pipeline
closely enough for the two to lie on top of each other: the same pressure
curve, stabilizer, minimum point spacing and filled-contour rasterisation. Each
frame's capture time says how far the video has caught up, and a stroke stops
being echoed once a frame that must already contain it has been painted.

Weylus is also patched to build against Ubuntu 24.04's FFmpeg 6.1; upstream
targets 7.1.

`matchbox-window-manager` runs so that Xournal++ can maximise; without a
window manager GTK leaves the window at its default size.

## Build

`Dockerfile` pins the Xournal++ and Weylus commits as build args; bump them
there. CI builds on push to `main` and publishes
`ghcr.io/advaypakhale/xournalpp-web:<commit>` and `:latest`.
