# syntax=docker/dockerfile:1
#
# Parliament triplestore, Jena 6.1 fork with tegmentum wf:call plugin bundled.
#
# Multi-stage:
#   1. boost-build:  compile Boost 1.86.0 from source with the naming
#                    convention Parliament's Jamfile expects
#                    (stage-gcc-ubuntu24/lib/libboost_*-gcc13-mt-x64-1_86.so.*)
#   2. rocksdb-build: build RocksDB 11.1 from source (Parliament pinned
#                    to this specific version).
#   3. builder:      pull JDK 25 + gradle + the two above, run the C++
#                    native build via bjam and the Java fat-JAR build via
#                    gradle. Produces the deployableServer tree.
#   4. runtime:      ubuntu:24.04 + JRE 25 + system libs Parliament links
#                    dynamically to (gflags, snappy, lz4, zstd, bz2, z,
#                    xxhash). Runs the fat JAR.
#
# Everything above the `builder` stage is expensive to build but cache-stable
# across source changes to Parliament itself — first build ~30-45 min, later
# rebuilds finish in a couple minutes.

# --- Stage 1: Boost 1.86.0 built from source ---------------------------------
ARG UBUNTU_TAG=25.10

FROM ubuntu:${UBUNTU_TAG} AS boost-build
ARG BOOST_VERSION=1_86_0
ARG BOOST_VERSION_DOTTED=1.86.0
ARG LINUX_DISTRO=ubuntu25
# arm64 native build (Apple Silicon). Parliament's site-config.jam uses this
# suffix in library filenames; b2 needs `architecture=arm` to produce them.
ARG BOOST_ARCH=a64

RUN apt-get -o Acquire::AllowInsecureRepositories=true \
        -o Acquire::AllowDowngradeToInsecureRepositories=true update \
    && apt-get -o Acquire::AllowInsecureRepositories=true \
        install -y --allow-unauthenticated --no-install-recommends \
        g++ gcc make wget ca-certificates bzip2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
RUN wget -q "https://archives.boost.io/release/${BOOST_VERSION_DOTTED}/source/boost_${BOOST_VERSION}.tar.bz2" \
    && tar xjf "boost_${BOOST_VERSION}.tar.bz2" \
    && rm "boost_${BOOST_VERSION}.tar.bz2"

WORKDIR /work/boost_${BOOST_VERSION}
RUN ./bootstrap.sh --with-toolset=gcc

# Recipe lifted from doc/UserGuide/Building.tex — --layout=versioned is
# what produces the "-gcc13-mt-x64-1_86" suffix Parliament's site-config.jam
# hardcodes; --ignore-site-config keeps the host boost config out; the
# BOOST_LOG_* defines are Parliament's chosen boost-log configuration.
RUN ./b2 -q -j$(nproc) \
        --disable-icu --ignore-site-config --layout=versioned \
        --build-dir=build-gcc-${LINUX_DISTRO} \
        --stagedir=stage-gcc-${LINUX_DISTRO} \
        --with-atomic --with-chrono --with-container --with-date_time \
        --with-filesystem --with-log --with-regex --with-serialization \
        --with-test --with-thread \
        define=BOOST_LOG_USE_STD_REGEX \
        define=BOOST_LOG_WITHOUT_SYSLOG \
        define=BOOST_LOG_WITHOUT_IPC \
        define=BOOST_LOG_WITHOUT_ASIO \
        define=BOOST_TEST_ALTERNATIVE_INIT_API \
        toolset=gcc address-model=64 \
        variant=release link=shared,static runtime-link=shared \
        architecture=arm cxxstd=20 stage

# --- Stage 2: RocksDB 11.1 built from source --------------------------------
FROM ubuntu:${UBUNTU_TAG} AS rocksdb-build
ARG ROCKSDB_VERSION=v11.1.1

RUN apt-get -o Acquire::AllowInsecureRepositories=true \
        -o Acquire::AllowDowngradeToInsecureRepositories=true update \
    && apt-get -o Acquire::AllowInsecureRepositories=true \
        install -y --allow-unauthenticated --no-install-recommends \
        g++ gcc make cmake git ca-certificates \
        libgflags-dev libsnappy-dev libz-dev libbz2-dev liblz4-dev \
        libzstd-dev libxxhash-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
RUN git clone --depth=1 --branch ${ROCKSDB_VERSION} https://github.com/facebook/rocksdb.git
WORKDIR /work/rocksdb
RUN mkdir -p build && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release \
             -DFAIL_ON_WARNINGS=OFF \
             -DCMAKE_CXX_FLAGS="-Wno-error=maybe-uninitialized -Wno-error=array-bounds -Wno-error=stringop-overflow" \
             -DWITH_SNAPPY=ON -DWITH_LZ4=ON -DWITH_ZSTD=ON -DWITH_ZLIB=ON \
             -DWITH_BZ2=ON -DWITH_GFLAGS=ON \
             -DWITH_TESTS=OFF -DWITH_BENCHMARK_TOOLS=OFF \
             -DCMAKE_INSTALL_PREFIX=/opt/rocksdb \
             .. \
    && make -j$(nproc) \
    && make install

# --- Stage 3: Java build (fat JAR + native libs) ----------------------------
FROM ubuntu:${UBUNTU_TAG} AS builder
ARG BOOST_VERSION=1_86_0
ARG LINUX_DISTRO=ubuntu25

RUN apt-get -o Acquire::AllowInsecureRepositories=true \
        -o Acquire::AllowDowngradeToInsecureRepositories=true update \
    && apt-get -o Acquire::AllowInsecureRepositories=true \
        install -y --allow-unauthenticated --no-install-recommends \
        g++ gcc make git ca-certificates wget patchelf \
        libgflags-dev libsnappy-dev libz-dev libbz2-dev liblz4-dev \
        libzstd-dev libxxhash-dev \
    && rm -rf /var/lib/apt/lists/*

# Java 25 (Adoptium Temurin) — matches jena-update targetCompatibility.
RUN wget -qO /tmp/temurin25.tar.gz \
        "https://api.adoptium.net/v3/binary/latest/25/ga/linux/aarch64/jdk/hotspot/normal/eclipse?project=jdk" \
    && mkdir -p /opt/java \
    && tar -xzf /tmp/temurin25.tar.gz -C /opt/java --strip-components=1 \
    && rm /tmp/temurin25.tar.gz
ENV JAVA_HOME=/opt/java
ENV PATH=$JAVA_HOME/bin:$PATH

# Boost.Build (bjam / b2).
COPY --from=boost-build /work/boost_${BOOST_VERSION}/tools/build /work/boost-build
RUN cd /work/boost-build && ./bootstrap.sh && ./b2 install --prefix=/usr/local
ENV PATH=/usr/local/bin:$PATH

# Prebuilt Boost libraries in the exact layout site-config.jam expects.
COPY --from=boost-build /work/boost_${BOOST_VERSION} /opt/boost
ENV BOOST_ROOT=/opt/boost
ENV BOOST_VERSION=${BOOST_VERSION}
ENV BOOST_ARCHITECTURE=a64
ENV LINUX_DISTRO=${LINUX_DISTRO}
ENV UBUNTU_USR_LIB=/usr/lib/aarch64-linux-gnu

# RocksDB. CMake installs librocksdb.so → librocksdb.so.11 → librocksdb.so.11.1.1
# but Parliament's site-config.jam hardcodes the "-11.1" suffix, so add the
# missing intermediate symlink.
COPY --from=rocksdb-build /opt/rocksdb /opt/rocksdb
RUN ln -sf librocksdb.so.11.1.1 /opt/rocksdb/lib/librocksdb.so.11.1
ENV ROCKSDB_HOME=/opt/rocksdb

# Boost.Build 5.x installed via `b2 install --prefix=/usr/local` looks up
# its config under /usr/local/share/boost-build/, not /usr/share/. Also set
# BOOST_BUILD_PATH explicitly so the resolver picks up site-config.jam even
# if the install path shifts.
COPY doc/Linux/site-config.jam /usr/local/share/boost-build/site-config.jam
COPY doc/Linux/user-config.jam /root/user-config.jam
ENV BOOST_BUILD_PATH=/usr/local/share/boost-build

# Prime the gradle wrapper distribution download in its own layer so a
# source edit doesn't require re-downloading ~200 MB of gradle every rebuild.
WORKDIR /parliament
COPY gradle /parliament/gradle
COPY gradlew /parliament/gradlew
RUN chmod +x /parliament/gradlew && /parliament/gradlew --version

# Source.
COPY . /parliament

# Full build: native (via bjam) + fat JAR (Spring Boot + wf plugin bundled).
RUN ./gradlew --no-daemon :server:bootJar

# --- Stage 4: runtime -------------------------------------------------------
# eclipse-temurin:25-jre already ships Java 25 + a slim Debian base, so we
# skip the wget-download and the JRE tarball unpack entirely. Only the tiny
# native runtime libs need installing.
FROM eclipse-temurin:25-jre AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
        libgflags2.2 libsnappy1v5 zlib1g libbz2-1.0 liblz4-1 libzstd1 libxxhash0 \
    && rm -rf /var/lib/apt/lists/*

RUN adduser --system --group --uid 1500 parliament \
    && mkdir -p /var/parliament-data /opt/parliament/lib /opt/parliament/config \
    && chown -R parliament:parliament /var/parliament-data /opt/parliament

# Fat JAR and native libs.
COPY --from=builder /parliament/server/build/libs/server-*.jar /opt/parliament/server.jar
COPY --from=builder /parliament/target/deployableServer/bin/ /opt/parliament/lib/
# RocksDB shared object needs to travel with us.
COPY --from=rocksdb-build /opt/rocksdb/lib/librocksdb.so* /opt/parliament/lib/
# Parliament's KbConfig.txt is loaded from the process's current working
# directory; drop the templates at the WORKDIR root, not under config/, so
# ParliamentBridge.init() finds them without a config-file env override.
COPY --from=builder /parliament/target/deployableServer/*.txt /opt/parliament/

USER parliament
ENV LD_LIBRARY_PATH=/opt/parliament/lib
EXPOSE 8089
VOLUME /var/parliament-data
WORKDIR /opt/parliament

ENTRYPOINT ["java", "-Djava.library.path=/opt/parliament/lib", \
            "-Xmx1g", "-jar", "/opt/parliament/server.jar"]
