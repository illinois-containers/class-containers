# CS 341 (System Programming) — Spring 2027 student environment
#
# A deliberately smaller image than cs341/fa26. Still glibc: the course
# teaches against glibc's malloc, pthreads and sanitizer behaviour, so musl
# bases (alpine) are out. Debian trixie-slim gives the same libc family in a
# much smaller base layer than a full Ubuntu image, with current toolchain
# packages.
#
# Deliberate difference from cs341/fa26 (Ubuntu 24.04, pinned to the grader
# image's versions): this offering does NOT inherit the Fall pins, because
# Debian's package versions differ. Whatever this image resolves to must be
# the version the Spring 2027 autograder uses too — see "Before this is used
# for grading" below.
#
# Digest-pinned so a rebuild is reproducible. Resolved 2026-09-19.
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

ENV DEBIAN_FRONTEND=noninteractive

# Package names are unversioned on purpose. Pinning requires knowing the exact
# versions Debian trixie currently ships, and inventing those strings would
# produce an image that fails to build. The first successful CI build records
# the resolved versions in the job summary; copy them into an apt_pins file
# here once they are known, the way cs341/fa26 does.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      # toolchain
      build-essential \
      clang \
      # debugging and analysis — the core of the course
      gdb \
      valgrind \
      strace \
      libc6-dbg \
      # MP dependencies
      libncurses-dev \
      rpcbind \
      python3 \
      # workflow
      git \
      iproute2 \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Non-root by default. The platform must override the UID per student:
# RLIMIT_NPROC (`ulimit -u`, which this course teaches) is enforced per *host*
# UID, so students sharing UID 1000 would share one process budget and one
# student's fork bomb would hit the others.
ARG STUDENT_USER=student
ARG STUDENT_UID=1000
RUN useradd -m -u "${STUDENT_UID}" -s /bin/bash "${STUDENT_USER}"
USER ${STUDENT_USER}
WORKDIR /home/${STUDENT_USER}
CMD ["/bin/bash"]

# ---------------------------------------------------------------------------
# Before this is used for grading
#
# 1. Sanitizer runtimes. ci-smoke.sh compiles with -fsanitize=address and
#    -fsanitize=thread. If Debian splits the clang runtime into a separate
#    package, that step fails loudly on the first build and the package gets
#    added here. This is checked rather than guessed on purpose.
#
# 2. 32-bit builds. Any MP using `-m32` needs gcc-multilib / libc6-dev-i386,
#    not installed here because it is unclear whether Spring 2027 still needs
#    it. Add it if so — it is a few tens of MB.
#
# 3. Version agreement with the autograder. Students must see the same libc
#    and sanitizer behaviour as the grader. Fall 2026 achieves this by sharing
#    pins with cs341-illinois/docker-base (Ubuntu 24.04). A Debian-based
#    Spring image needs the same agreement re-established, or the grader
#    rebased onto this image.
#
# 4. ThreadSanitizer may need the host sysctl vm.mmap_rnd_bits=28 on newer
#    kernels. A container cannot set this for itself; it belongs to whoever
#    runs the hosts.
#
# Not included, deliberately: sshd (login is the platform's job, and baking it
# in risks shipping one host key to every student), cmake (add if an MP's build
# needs it), pip (add a venv layer if an MP needs it).
# ---------------------------------------------------------------------------
