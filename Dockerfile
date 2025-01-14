FROM ghcr.io/linuxserver/baseimage-alpine:arm64v8-3.19 as buildstage

ARG KASMVNC_RELEASE="v1.2.0"

RUN \
    echo "**** install build deps ****" && \
    apk add \
    alpine-release \
    alpine-sdk \
    autoconf \
    automake \
    bash \
    ca-certificates \
    cmake \
    coreutils \
    curl \
    eudev-dev \
    font-cursor-misc \
    font-misc-misc \
    font-util-dev \
    git \
    grep \
    jq \
    libdrm-dev \
    libepoxy-dev \
    libjpeg-turbo-dev \
    libjpeg-turbo-static \
    libpciaccess-dev \
    libtool \
    libwebp-dev \
    libx11-dev \
    libxau-dev \
    libxcb-dev \
    libxcursor-dev \
    libxcvt-dev \
    libxdmcp-dev \
    libxext-dev \
    libxfont2-dev \
    libxkbfile-dev \
    libxrandr-dev \
    libxshmfence-dev \
    libxtst-dev \
    mesa-dev \
    mesa-dri-gallium \
    meson \
    nettle-dev \
    openssl-dev \
    pixman-dev \
    procps \
    shadow \
    tar \
    tzdata \
    wayland-dev \
    wayland-protocols \
    xcb-util-dev \
    xcb-util-image-dev \
    xcb-util-keysyms-dev \
    xcb-util-renderutil-dev \
    xcb-util-wm-dev \
    xinit \
    xkbcomp \
    xkbcomp-dev \
    xkeyboard-config \
    xorgproto \
    xorg-server-common \
    xorg-server-dev \
    xtrans

RUN \
    echo "**** build libjpeg-turbo ****" && \
    mkdir /jpeg-turbo && \
    JPEG_TURBO_RELEASE=$(curl -sX GET "https://api.github.com/repos/libjpeg-turbo/libjpeg-turbo/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
    curl -o \
    /tmp/jpeg-turbo.tar.gz -L \
    "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/${JPEG_TURBO_RELEASE}.tar.gz" && \
    tar xf \
    /tmp/jpeg-turbo.tar.gz -C \
    /jpeg-turbo/ --strip-components=1 && \
    cd /jpeg-turbo && \
    MAKEFLAGS=-j`nproc` \
    CFLAGS="-fpic" \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -G"Unix Makefiles" && \
    make && \
    make install

RUN \
    echo "**** build kasmvnc ****" && \
    git clone https://github.com/kasmtech/KasmVNC.git src && \
    cd /src && \
    git checkout -f ${KASMVNC_release} && \
    sed -i \
    -e '/find_package(FLTK/s@^@#@' \
    -e '/add_subdirectory(tests/s@^@#@' \
    CMakeLists.txt && \
    cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBUILD_VIEWER:BOOL=OFF \
    -DENABLE_GNUTLS:BOOL=OFF \
    . && \
    make -j4 && \
    echo "**** build xorg ****" && \
    XORG_VER="1.20.14" && \
    XORG_PATCH=$(echo "$XORG_VER" | grep -Po '^\d.\d+' | sed 's#\.##') && \
    wget --no-check-certificate \
    -O /tmp/xorg-server-${XORG_VER}.tar.gz \
    "https://www.x.org/archive/individual/xserver/xorg-server-${XORG_VER}.tar.gz" && \
    tar --strip-components=1 \
    -C unix/xserver \
    -xf /tmp/xorg-server-${XORG_VER}.tar.gz && \
    cd unix/xserver && \
    patch -Np1 -i ../xserver${XORG_PATCH}.patch && \
    patch -s -p0 < ../CVE-2022-2320-v1.20.patch && \
    autoreconf -i && \
    ./configure \
    --disable-config-hal \
    --disable-config-udev \
    --disable-dmx \
    --disable-dri \
    --disable-dri2 \
    --disable-kdrive \
    --disable-static \
    --disable-xephyr \
    --disable-xinerama \
    --disable-xnest \
    --disable-xorg \
    --disable-xvfb \
    --disable-xwayland \
    --disable-xwin \
    --enable-dri3 \
    --enable-glx \
    --prefix=/opt/kasmweb \
    --with-default-font-path="/usr/share/fonts/X11/misc,/usr/share/fonts/X11/cyrillic,/usr/share/fonts/X11/100dpi/:unscaled,/usr/share/fonts/X11/75dpi/:unscaled,/usr/share/fonts/X11/Type1,/usr/share/fonts/X11/100dpi,/usr/share/fonts/X11/75dpi,built-ins" \
    --without-dtrace \
    --with-sha1=libcrypto \
    --with-xkb-bin-directory=/usr/bin \
    --with-xkb-output=/var/lib/xkb \
    --with-xkb-path=/usr/share/X11/xkb && \
    find . -name "Makefile" -exec sed -i 's/-Werror=array-bounds//g' {} \; && \
    make -j4

RUN \
    echo "**** generate final output ****" && \
    cd /src && \
    mkdir -p xorg.build/bin && \
    cd xorg.build/bin/ && \
    ln -s /src/unix/xserver/hw/vnc/Xvnc Xvnc && \
    cd .. && \
    mkdir -p man/man1 && \
    touch man/man1/Xserver.1 && \
    cp /src/unix/xserver/hw/vnc/Xvnc.man man/man1/Xvnc.1 && \
    mkdir lib && \
    cd lib && \
    ln -s /usr/lib/xorg/modules/dri dri && \
    cd /src && \
    mkdir -p builder/www && \
    # cp -ax /www/* builder/www/ && \
    make servertarball && \
    mkdir /build-out && \
    tar xzf \
    kasmvnc-Linux*.tar.gz \
    -C /build-out/

# runtime stage
FROM ghcr.io/linuxserver/baseimage-alpine:arm64v8-3.19

# set version label
ARG BUILD_DATE
ARG VERSION
ARG KASMBINS_RELEASE="1.14.0"
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"
LABEL "com.kasmweb.image"="true"

# env
ENV DISPLAY=:1 \
    PERL5LIB=/usr/local/bin \
    OMP_WAIT_POLICY=PASSIVE \
    GOMP_SPINCOUNT=0 \
    PULSE_RUNTIME_PATH=/defaults \
    NVIDIA_DRIVER_CAPABILITIES=all

# copy over build output
COPY --from=buildstage /build-out/ /

RUN \
    echo "**** install deps ****" && \
    apk add --no-cache \
    bash \
    ca-certificates \
    dbus-x11 \
    ffmpeg \
    font-noto \
    fuse-overlayfs \
    gcompat \
    libgcc \
    libgomp \
    libjpeg-turbo \
    libstdc++ \
    libwebp \
    libxfont2 \
    libxshmfence \
    mcookie \
    mesa \
    mesa-dri-gallium \
    mesa-gbm \
    mesa-gl \
    nginx \
    openbox \
    openssh-client \
    openssl \
    pciutils-libs \
    perl \
    perl-datetime \
    perl-hash-merge-simple \
    perl-list-moreutils \
    perl-switch \
    perl-try-tiny \
    perl-yaml-tiny \
    pixman \
    pulseaudio \
    pulseaudio-utils \
    py3-xdg \
    python3 \
    setxkbmap \
    sudo \
    tar \
    xauth \
    xf86-video-amdgpu \
    xf86-video-ati \
    xf86-video-nouveau \
    xkbcomp \
    xkeyboard-config && \
    # xterm && \
    echo "**** filesystem setup ****" && \
    ln -s /usr/local/share/kasmvnc /usr/share/kasmvnc && \
    ln -s /usr/local/etc/kasmvnc /etc/kasmvnc && \
    ln -s /usr/local/lib/kasmvnc /usr/lib/kasmvncserver && \
    echo "**** openbox tweaks ****" && \
    sed -i \
    's/NLIMC/NLMC/g' \
    /etc/xdg/openbox/rc.xml && \
    echo "**** kasm support ****" && \
    useradd \
    -u 1000 -U \
    -d /home/kasm-user \
    -s /bin/bash kasm-user && \
    # echo "kasm-user:kasm" | chpasswd && \
    adduser kasm-user wheel && \
    mkdir -p /home/kasm-user && \
    chown 1000:1000 /home/kasm-user && \
    mkdir -p /var/run/pulse && \
    chown 1000:root /var/run/pulse && \
    mkdir -p /kasmbins && \
    curl -s https://kasm-ci.s3.amazonaws.com/kasmbins-arm64-${KASMBINS_RELEASE}.tar.gz \
    | tar xzvf - -C /kasmbins/ && \
    chmod +x /kasmbins/* && \
    chown -R 1000:1000 /kasmbins && \
    echo 'hosts: files dns' > /etc/nsswitch.conf && \
    echo "**** chromium setup ****" && \
    apk add --no-cache chromium && \
    echo "**** cleanup ****" && \
    rm -rf \
    /tmp/*

RUN echo "**** local fonts ****" && \
    apk add --no-cache font-terminus font-noto font-noto-extra font-arabic-misc && \
    apk add --no-cache font-misc-cyrillic font-mutt-misc font-screen-cyrillic font-winitzki-cyrillic font-cronyx-cyrillic && \
    apk add --no-cache font-noto-arabic font-noto-armenian font-noto-cherokee font-noto-devanagari font-noto-ethiopic font-noto-georgian && \
    apk add --no-cache font-noto-hebrew font-noto-lao font-noto-malayalam font-noto-tamil font-noto-thaana

# add local files
COPY /root /