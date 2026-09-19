# CS 341 (System Programming) — Fall 2026 student environment
#
# Derived from https://github.com/cs341-illinois/docker-base (the course's
# grader image), trimmed for use as an interactive student environment.
# Deltas from upstream are listed at the bottom of this file.
#
# Base: Ubuntu 26.04, matching the student VMs (26.04.1). Note that the grader
# image is still Ubuntu 24.04 with clang-18 pins, so THIS IMAGE AND THE GRADER
# CURRENTLY DIFFER — see "Before this is used for grading" below. Staying on
# glibc matters more than the exact release: the course teaches against glibc's
# malloc, pthreads and sanitizer behaviour, so a musl base is out.
#
# Digest-pinned so a rebuild is reproducible; refresh deliberately, not by
# accident. Resolved 2026-09-19.
FROM ubuntu:26.04@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78

ENV DEBIAN_FRONTEND=noninteractive

# Package names are unversioned on purpose. The course's existing apt_pins name
# 24.04 versions (clang-18 1:18.1.3, valgrind 3.22.0, libc6-dbg 2.39) which do
# not exist in 26.04; pinning to them with Pin-Priority 1001 would fail the
# build. The first successful CI build records the resolved versions in the job
# summary — copy those into an apt_pins file here once they are known, and
# update the grader image to match.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      # toolchain
      build-essential \
      clang \
      libclang-rt-dev \
      cmake \
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
    #
    # Architecture-specific libc.a symlink (upstream behaviour, retained)
    #
    BUILD_ARCH="$(dpkg --print-architecture)" && \
    case "${BUILD_ARCH}" in \
      amd64) ln -sf /usr/lib/x86_64-linux-gnu/libc.a /usr/lib/x86_64-linux-gnu/liblibc.a ;; \
      arm64) ln -sf /usr/lib/aarch64-linux-gnu/libc.a /usr/lib/aarch64-linux-gnu/liblibc.a ;; \
      *) echo "Unsupported architecture: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac && \
    rm -rf /var/lib/apt/lists/*

# Non-root by default. The platform is expected to override the UID per
# student: `ulimit -u` / RLIMIT_NPROC (which this course teaches) is enforced
# per *host* UID, so every student container sharing UID 1000 would share one
# process budget and one student's fork bomb would hit the others.
ARG STUDENT_USER=student
ARG STUDENT_UID=1000
RUN if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu 2>/dev/null || true; fi && \
    useradd -m -u "${STUDENT_UID}" -s /bin/bash "${STUDENT_USER}"
USER ${STUDENT_USER}
WORKDIR /home/${STUDENT_USER}
CMD ["/bin/bash"]

# ---------------------------------------------------------------------------
# Before this is used for grading
#
# 1. Version agreement with the autograder. Students must see the same libc and
#    sanitizer behaviour as the grader. cs341-illinois/docker-base is Ubuntu
#    24.04 / clang-18; this image is 26.04. Either rebase the grader onto this
#    image, or accept the difference knowingly. Do not leave it unnoticed.
#
# 2. Regenerate apt_pins from the first successful build (see the RUN comment).
#    The old 24.04 pins file was removed rather than carried forward broken.
#
# 3. Sanitizer runtimes. ci-smoke.sh compiles with -fsanitize=address and
#    -fsanitize=thread; if 26.04 splits the clang runtime into its own package,
#    that step fails loudly on the first build and the package gets added here.
#
# 4. 32-bit builds. Any MP using `-m32` needs gcc-multilib / libc6-dev-i386,
#    not installed here. Add it if Fall 2026 still uses it.
#
# 5. ThreadSanitizer may need the host sysctl vm.mmap_rnd_bits=28 on newer
#    kernels. A container cannot set this for itself; it belongs to whoever
#    runs the hosts.
#
# Deltas from cs341-illinois/docker-base
#
# Added:   gdb (the course's primary debugger; the grader does not need it
#          interactively), ca-certificates, a non-root user, digest-pinned base
# Removed: software-properties-common (~100 MB of python/dbus plumbing, only
#          needed to add PPAs at build time; none are added here),
#          python3-pip (large dependency tree; add a venv layer if an MP needs
#          it), wget and bzip2 (not referenced by any MP)
# Kept:    cmake, despite its size, because upstream ships it
# Changed: unversioned clang instead of clang-18 (see the pins note above)
#
# NOT included, deliberately: sshd — login is the platform's job, and baking it
# in risks shipping one host key to every student.
# ---------------------------------------------------------------------------
