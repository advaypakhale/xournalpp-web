# syntax=docker/dockerfile:1.7

ARG XOURNALPP_REF=19dd803150931eed6dc856b2c57d1c9eb8c95394
ARG WEYLUS_REF=38a01a8f8e429500c7e9f67fc1c88ca37a4d1e93
ARG RUST_VERSION=1.89.0

FROM ubuntu:24.04 AS xournalpp
ARG XOURNALPP_REF
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git gcc g++ cmake ninja-build pkg-config gettext help2man \
    librsvg2-dev libgtk-3-dev libpoppler-glib-dev portaudio19-dev libsndfile1-dev \
    liblua5.3-dev libzip-dev libgtksourceview-4-dev libqpdf-dev libxml2-dev
RUN git clone https://github.com/advaypakhale/xournalpp.git /src \
    && git -C /src checkout --detach "$XOURNALPP_REF"
WORKDIR /src
RUN cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
    && ninja -C build \
    && DESTDIR=/out ninja -C build install

FROM ubuntu:24.04 AS weylus
ARG WEYLUS_REF
ARG RUST_VERSION
ENV DEBIAN_FRONTEND=noninteractive RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git curl gcc g++ make cmake pkg-config clang node-typescript \
    libavcodec-dev libavformat-dev libavdevice-dev libavfilter-dev libavutil-dev \
    libswscale-dev libswresample-dev libx264-dev libva-dev libdrm-dev \
    libx11-dev libxext-dev libxrandr-dev libxfixes-dev libxcomposite-dev libxi-dev \
    libxcb-dri3-dev libxft-dev libxinerama-dev libxcursor-dev libxrender-dev libxtst-dev \
    libgl1-mesa-dev libglu1-mesa-dev libpango1.0-dev libwayland-dev libxkbcommon-dev \
    libdbus-1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libssl-dev
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION"
RUN git clone https://github.com/H-M-H/Weylus.git /src \
    && git -C /src checkout --detach "$WEYLUS_REF"
WORKDIR /src
COPY weylus/ /patches/
RUN for p in /patches/*.patch; do git apply --verbose "$p"; done
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --release --features ffmpeg-system \
    && install -m 0755 target/release/weylus /usr/local/bin/weylus

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    xserver-xorg-core xserver-xorg-video-dummy xserver-xorg-input-evdev x11-xserver-utils \
    matchbox-window-manager \
    libgtk-3-0t64 libpoppler-glib8t64 libportaudio2 libportaudiocpp0 libsndfile1 liblua5.3-0 libzip4t64 \
    libgtksourceview-4-0 librsvg2-2 librsvg2-common libqpdf29t64 libxml2 \
    libavcodec60 libavformat60 libavdevice60 libavfilter9 libavutil58 libswscale7 libswresample4 \
    libx264-164 libva2 libva-drm2 libva-x11-2 libdrm2 libxcb-dri3-0 \
    libxft2 libxinerama1 libxcursor1 libxtst6 libpango-1.0-0 libpangoxft-1.0-0 libgl1 libglu1-mesa \
    libdbus-1-3 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 libgstreamer-gl1.0-0 \
    libxkbcommon0 libwayland-client0 libwayland-cursor0 libwayland-egl1 \
    fonts-dejavu-core fonts-noto-core adwaita-icon-theme shared-mime-info \
    && rm -rf /var/lib/apt/lists/*
COPY --from=xournalpp /out/ /
COPY --from=weylus /usr/local/bin/weylus /usr/local/bin/weylus
COPY rootfs/ /
RUN update-mime-database /usr/share/mime

ENV SCREEN=1920x1080 \
    WEYLUS_ACCESS_CODE= \
    XDG_CONFIG_HOME=/data/config \
    XDG_DATA_HOME=/data/share \
    XDG_CACHE_HOME=/tmp/cache \
    GSETTINGS_BACKEND=memory \
    DISPLAY=:0
VOLUME /data
EXPOSE 1701
ENTRYPOINT ["/usr/local/bin/entrypoint"]
