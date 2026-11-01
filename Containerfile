# Build environment for the LWJGL linux-x86 (32-bit) natives.
# Debian 12: 64-bit tools, i386 multiarch libraries, gcc -m32. The output needs glibc >= 2.36.
FROM docker.io/library/debian:bookworm

RUN dpkg --add-architecture i386 && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential gcc-multilib g++-multilib cmake ninja-build meson pkg-config git ca-certificates curl xz-utils \
        unzip python3 autoconf automake libtool file binutils \
        libwayland-bin wayland-protocols \
        libx11-dev:i386 libxrandr-dev:i386 libxinerama-dev:i386 libxcursor-dev:i386 libxi-dev:i386 libxext-dev:i386 \
        libxkbcommon-dev:i386 libwayland-dev:i386 \
        libasound2-dev:i386 libpulse-dev:i386 libpipewire-0.3-dev:i386 libjack-jackd2-dev:i386 portaudio19-dev:i386 \
        libdbus-1-dev:i386 \
    && rm -rf /var/lib/apt/lists/*

# JDK 25 + Ant for LWJGL's build (Kotlin templates, generator, javac).
RUN curl -fsSL -o /tmp/jdk.tgz https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz \
    && echo "68982529869257d0ee6b824ec5aa270ff8b118bb438670da0b97ebdab178d7fb  /tmp/jdk.tgz" | sha256sum -c - \
    && mkdir /opt/jdk && tar -xzf /tmp/jdk.tgz -C /opt/jdk --strip-components=1 && rm /tmp/jdk.tgz \
    && curl -fsSL -o /tmp/ant.tgz https://archive.apache.org/dist/ant/binaries/apache-ant-1.10.15-bin.tar.gz \
    && echo "d78427aff207592c024ff1552dc04f7b57065a195c42d398fcffe7a0145e8d00cd46786f5aa52e77ab0fdf81334f065eb8011eecd2b48f7228e97ff4cb20d16c  /tmp/ant.tgz" | sha512sum -c - \
    && mkdir /opt/ant && tar -xzf /tmp/ant.tgz -C /opt/ant --strip-components=1 && rm /tmp/ant.tgz

ENV JAVA_HOME=/opt/jdk PATH=/opt/jdk/bin:/opt/ant/bin:$PATH LWJGL_X86_CONTAINER=1
