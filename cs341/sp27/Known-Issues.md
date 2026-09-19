# cs341/sp27 — known issues

What is actually known about this image, as opposed to assumed. Updated 2026-09-19.

**Images published from this offering**

| tag | platform | for |
|---|---|---|
| `cs341:sp27-img1` | amd64 | students, graders, the farm |
| `cs341:sp27-img1-arm64dev` | arm64 | staff on Apple-silicon laptops — **never grading, never students** |

Pin the digest, not the tag: the plain tag moves when staff publish an update.

---

## 1. AddressSanitizer's leak detection does not work on arm64

**Confirmed** by building this Dockerfile natively on arm64 and running the smoke test: a program that leaks 32 bytes produces **no leak report at all**, while the same image on amd64 reports it correctly. There is no error message — the check simply passes.

This is why the arm64 image is labelled `-arm64dev` and why `multiarch` is off. A student given an arm64 image would see silence where the grader expects a diagnostic, which is the worst failure mode available: nothing to search for, nothing to ask about.

The smoke test prints `KNOWN` rather than `FAIL` for this on arm64, so the arm64 build stays green while the limitation stays visible.

## 2. A Mac cannot validate this image

On Apple silicon the amd64 image runs under emulation, where two things break that work fine on real amd64:

- **ThreadSanitizer refuses to start**: `FATAL: ThreadSanitizer: memory layout is incompatible, even though ASLR is disabled`.
- **gdb cannot ptrace**: `Cannot PTRACE_GETREGS: Input/output error`, even with `--cap-add=SYS_PTRACE --security-opt seccomp=unconfined`.

A Mac can confirm the image builds and the toolchain runs. It cannot confirm the debugging tools this course is about. Use the `-arm64dev` image for local work, and real amd64 for anything you intend to believe.

## 3. gdb attaching to a running process needs SYS_PTRACE

Launching a program *under* gdb works unprivileged. Attaching to an already-running process — and `strace` — needs the capability:

```
docker run --cap-add=SYS_PTRACE ...
# Kubernetes:
#   securityContext: { capabilities: { add: ["SYS_PTRACE"] } }
```

Without it the failure is `Operation not permitted`. Whether the course's MPs require attaching is **not yet confirmed with the instructor**.

## 4. ThreadSanitizer may need a host sysctl

TSan's shadow memory can collide with address-space randomisation on newer kernels; the fix is `vm.mmap_rnd_bits=28` **on the host**, which a container cannot set for itself. It was not needed on GitHub's runners. If TSan reports `unable to mmap` on the farm, this is why.

## 5. Package versions are not pinned

Unlike `cs341/fa26`, which inherited the course's pins, this offering installs unversioned packages. The first build resolved:

| | version |
|---|---|
| clang | 19.1.7 (Debian) |
| gcc | 14.2.0 |
| glibc | 2.41 |
| gdb | 16.3 |
| valgrind | 3.24.0 |
| python3 | 3.13.5 |

Turn these into an `apt_pins` file before the semester starts, or a mid-semester rebuild can hand students a different toolchain than the one they started on.

## 6. This image does not match the autograder

The course's grader image (`cs341-illinois/docker-base`) is Ubuntu 24.04 with clang-18 and glibc 2.39. This image is Debian trixie with clang 19.1.7 and glibc 2.41. **Students and the grader would see different libc and sanitizer behaviour.** Either rebase the grader onto this image, or decide knowingly to accept the difference. It is not resolved.

## 7. `-m32` is not installed

Any MP using 32-bit builds needs `gcc-multilib` / `libc6-dev-i386`, which are not in the image because it is unclear whether Spring 2027 needs them. Add if so.

## 8. Nothing about memory has been measured under load

The image builds, starts and passes its smoke test. Its behaviour under a real MP workload — peak memory, whether a 2 GB cap is right, how many fit on a host — is **unmeasured**. Run `bigtest.sh` on the target hardware and `../../scripts/farm-loadtest.sh` for density; see [docs/BIGTEST.md](../../docs/BIGTEST.md).

Related: `nproc` inside a container reports the **host's** CPU count, so `make -j$(nproc)` under a CPU limit will overcommit. `bigtest.sh` derives its job count from `cpu.max` instead.

## 9. Login, home directories and per-student UIDs are not this image's job

The image has no sshd and creates a single non-root `student` user. Whoever runs the platform must give each student **a distinct host UID** — `RLIMIT_NPROC` (`ulimit -u`, which this course teaches) is enforced per host UID, so students sharing one share a process budget and one fork bomb takes out the rest.
