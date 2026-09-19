# CS 341 (System Programming) — Fall 2026 student environment
#
# Derived from https://github.com/cs341-illinois/docker-base (the course's
# existing grader image), trimmed for use as an interactive student
# environment. Deltas from upstream are listed at the bottom of this file.
#
# The base stays Ubuntu 24.04 deliberately: the course's apt pins name
# Ubuntu 24.04 package versions (clang-18 1:18.1.3, valgrind 3.22.0,
# libc6-dbg 2.39), and students must see the same libc and sanitizer
# behaviour as the grader. A smaller base (debian-slim, alpine) would change
# the libc and break that guarantee, so "minimal" here means fewer packages,
# not a different distro.
#
# Digest-pinned so a rebuild is reproducible; refresh deliberately, not by
# accident. Resolved 2026-09-19.
FROM ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3

# Version pins shared with the grader image and with the EngrIT VM build.
# Keep in sync with https://github.com/cs341-illinois/docker-base/blob/main/apt_pins
COPY apt_pins /etc/apt/preferences.d/build_tools_pins

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      # toolchain
      build-essential \
      clang-18 \
      cmake \
      # debugging and analysis — the core of the course
      gdb \
      valgrind \
      strace \
      libc6-dbg \
      # MP dependencies
      libncurses-dev \
      libncurses6 \
      rpcbind \
      python3.12 \
      # workflow
      git \
      iproute2 \
      ca-certificates && \
    #
    # python3 -> 3.12 (upstream does the same; keeps `python3` predictable)
    #
    rm -f /usr/bin/python3 && \
    ln -s python3.12 /usr/bin/python3 && \
    #
    # Architecture-specific libc.a symlink (upstream behaviour, retained)
    #
    BUILD_ARCH="$(dpkg --print-architecture)" && \
    case "${BUILD_ARCH}" in \
      amd64) ln -sf /usr/lib/x86_64-linux-gnu/libc.a /usr/lib/x86_64-linux-gnu/liblibc.a ;; \
      arm64) ln -sf /usr/lib/aarch64-linux-gnu/libc.a /usr/lib/aarch64-linux-gnu/liblibc.a ;; \
      *) echo "Unsupported architecture: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac && \
    #
    # Unversioned clang so the grader and student muscle memory both work
    #
    ln -sf /usr/bin/clang-18 /usr/bin/clang && \
    ln -sf /usr/bin/clang++-18 /usr/bin/clang++ && \
    #
    rm -rf /var/lib/apt/lists/*

# Non-root by default. The platform is expected to override the UID per
# student: `ulimit -u` / RLIMIT_NPROC is enforced per *host* UID, so every
# student container sharing UID 1000 would share one process budget — and
# CS 341 teaches that limit. See docs/DESIGN.md.
ARG STUDENT_USER=student
ARG STUDENT_UID=1000
RUN if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu 2>/dev/null || true; fi && \
    useradd -m -u "${STUDENT_UID}" -s /bin/bash "${STUDENT_USER}"
USER ${STUDENT_USER}
WORKDIR /home/${STUDENT_USER}
CMD ["/bin/bash"]

# ---------------------------------------------------------------------------
# Deltas from cs341-illinois/docker-base
#
# Added:
#   gdb             — the course's primary debugger; absent upstream because
#                     the grader does not need it interactively
#   ca-certificates — https (git clone, pip) fails without it
#   non-root user   — upstream runs as root, acceptable for a grader,
#                     not for a student environment
#   digest-pinned base
#
# Removed:
#   software-properties-common — ~100 MB of python/dbus plumbing, used only to
#                     add PPAs at build time; no PPA is added here
#   python3-pip     — pulls a large dependency tree; add it in a later layer
#                     if an MP needs it
#   wget, bzip2     — not referenced by any MP; `curl` is not installed either,
#                     add deliberately if a handout needs a download
#
# Kept despite size:
#   cmake           — upstream ships it and some MPs' build files use it
#
# NOT included, and deliberately so — these are runtime/platform concerns,
# not image concerns:
#   sshd            — login is the platform's job. Baking sshd in also risks
#                     shipping one host key to every student (a defect found
#                     in the draft images this repo replaces).
#   ThreadSanitizer host setting — TSan may need vm.mmap_rnd_bits=28 on newer
#                     host kernels. That is a host sysctl; it cannot be set
#                     from inside a container. See docs/DESIGN.md.
# ---------------------------------------------------------------------------
