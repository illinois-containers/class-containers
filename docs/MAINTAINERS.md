# Maintainers

Repository setup, semester rollover, retention, and the things known to be wrong before the first image is ever built.

For why any of this is shaped the way it is, see [DESIGN.md](DESIGN.md).

## One-time setup

### Repository variables

Settings → Secrets and variables → Actions → Variables. These are **variables**, not secrets; nothing here is sensitive and nothing here needs to be.

| Variable | Value | Meaning |
|---|---|---|
| `REGISTRY` | `ghcr.io` | Registry host. Set so the whole scheme can move without editing every file. |
| `ACTIVE_SEMESTERS` | e.g. `fa26 sp27` | Semesters the weekly scheduled rebuild is allowed to touch. |

`ACTIVE_SEMESTERS` is one of two independent brakes: the weekly rebuild runs an offering only if its status is `active` **and** its semester is listed here. One person forgetting one of the two does not resurrect a two-year-old image.

### CODEOWNERS

`/CODEOWNERS` at the repo root maps each class directory to its instructor. It is the **only** place ownership is recorded — `image.yml` has no `owners` field, deliberately. Enable "Require review from Code Owners" in the branch protection rule for `main` so the mapping is enforced rather than advisory.

Onboarding an instructor is uncommenting one line in that file.

### The `unfreeze` label

Create a repository label named exactly `unfreeze` (Issues → Labels → New label). Validation **fails** any pull request that touches a frozen offering unless the PR carries it. Without the label existing, a legitimate fix to an old semester cannot be merged.

Use it rarely and say in the PR why an archived semester is being changed.

### Workflow permissions

Leave the repository default workflow permissions at **read-only** (Settings → Actions → General → Workflow permissions). The build workflow grants `permissions: packages: write` at the job level, which is how it can push to GHCR without the whole repository's workflows being able to. This is intentional; do not "fix" it by widening the default.

No secrets are configured, and none should be. Pushing to GHCR uses the automatic `GITHUB_TOKEN`.

### Make each new package public — the step that surprises everyone

**GHCR creates a package as private on its first push, even for a public repository.** The build succeeds, the tag exists, the workflow is green, and students get `denied` or `not found` when they pull. Nothing in the logs says why.

Once per **package name** (so once per `<class>:<semester>-<subname>`), after the first successful push to `main`:

1. Org page → **Packages** → select the package (e.g. `cs341:fa26-img1`)
2. **Package settings**
3. **Change visibility** → **Public** → confirm by typing the package name

While there, under **Manage Actions access**, confirm this repository has Write access to the package — GHCR usually links it automatically on first push from the repo, but not always.

Verify anonymously, from a machine that is not logged in:

```
docker logout ghcr.io
docker pull ghcr.io/illinois-containers/cs341:fa26-img1
```

Do this before telling students the image exists. A new subname is a new package name and needs the same step again.

## Semester rollover

When Fall 2026 ends and Spring 2027 starts:

1. **Freeze the finished offering.** Add to `cs341/fa26/image.yml` (creating the file if the offering did not have one):

   ```yaml
   status: frozen
   ```

   Frozen means: never rebuilt on a schedule, rebuildable only by `workflow_dispatch` with the `force` flag, and any PR touching the directory fails validation without the `unfreeze` label.

2. **Add the new offering.** Usually the instructor does this via a pull request — see [ADDING-AN-OFFERING.md](ADDING-AN-OFFERING.md). `scripts/new-offering.sh cs341 sp27` is the copy step.

3. **Update `ACTIVE_SEMESTERS`.** Add the new semester; remove the finished one. Removing it is the second brake, and it is the half that catches a forgotten freeze.

4. **Make the new package public** if the subname is new (see above), and verify an anonymous pull.

5. **Update CODEOWNERS** if the instructor changed.

Both the freeze and the `ACTIVE_SEMESTERS` edit are meant to happen. Doing only one of them is safe; that is the design.

## Retention

**Never prune a frozen offering's images.** The published image is the archive — not the Dockerfile. An old offering may eventually stop rebuilding at all, because apt repositories drift and end-of-life mirrors disappear, so the registry holds the only copy of what those students actually ran.

| | |
|---|---|
| Frozen offerings' tagged versions | Keep indefinitely. Do not prune, ever. |
| Active offerings' dated tags | Keep. They are small deltas and they are how you answer "what changed last Tuesday?". |
| Untagged versions from superseded builds of an **active** offering | Safe to prune after a few weeks. |
| Untagged versions belonging to a **frozen** offering | Do not prune — a student may have pinned that digest. |

If a retention policy or cleanup action is ever added, it must be able to tell frozen offerings apart and exclude them. Until such a policy exists and has been reviewed, delete nothing.

Deleting a package version breaks every digest pin to it, silently and permanently. There is no undo.

## Known issues before first build

Most of the list below came from design notes and course materials. Where something has since been tested, it says so.

### Both cs341 images now build, and their smoke tests pass on amd64

First built 2026-09-19. The first run found two real defects, both fixed: the clang sanitizer runtimes live in a separate package (`libclang-rt-dev`) on both distros, and the fa26 smoke test still asserted clang 18.1.3 from the removed 24.04 pins.

Resolved toolchains — these are what a future `apt_pins` file should be built from:

| | base | clang | glibc |
|---|---|---|---|
| `cs341/fa26` | Ubuntu 26.04 | 21.1.8 | 2.43 |
| `cs341/sp27` | Debian trixie-slim | 19.1.7 | 2.41 |

Still unmeasured: everything about memory under real workloads. Run `bigtest.sh` on the target hardware — see [BIGTEST.md](BIGTEST.md).

### Do not publish arm64 images for cs341

Tested 2026-09-19 on an arm64 Mac, building the same Dockerfile natively: **AddressSanitizer's leak detection silently fails to report a leak** that the same image reports correctly on amd64. A student on such an image would see nothing where the grader expects a leak report — a failure with no error message. `multiarch` stays `false` for this class.

### A Mac cannot validate these images

On an Apple-silicon Mac the amd64 image runs under emulation, where ThreadSanitizer refuses to start (`memory layout is incompatible`) and gdb cannot ptrace (`Cannot PTRACE_GETREGS`), even with `--cap-add=SYS_PTRACE --security-opt seccomp=unconfined`. Both work on real amd64. A Mac can confirm the image builds and the toolchain runs; it cannot confirm the debugging tools this course is about.

### gdb needs SYS_PTRACE granted

Attaching gdb or strace to a *running* process needs `--cap-add=SYS_PTRACE` (Kubernetes: `securityContext.capabilities.add: ["SYS_PTRACE"]`). Without it the container refuses with "Operation not permitted". Launching a program under gdb works unprivileged.

Related: the course's grader image, `cs341-illinois/docker-base`, is still Ubuntu 24.04 with clang-18. **Both offerings here currently differ from the grader.** Either the grader gets rebased, or the difference is accepted knowingly. It is written in both Dockerfiles so it cannot be accepted quietly.

### `make -j$(nproc)` is the likeliest cause of an OOM

Inside a container, `nproc` reports the **host's** CPU count, not the container's CPU quota. On a 64-core host, a student container limited to 2 CPUs and 2 GB still runs `make -j64`, spawns 64 compiler processes, and is OOM-killed — while the limits look generous and the Makefile looks ordinary.

This is the first thing to check when a build dies inside a container and works outside it. `bigtest.sh` derives its parallelism from `cpu.max` instead of `nproc` for exactly this reason; see [BIGTEST.md](BIGTEST.md). Student-facing Makefiles that hardcode `-j$(nproc)` are a course-materials problem, not an image problem, and worth raising with the instructor.

### ThreadSanitizer may need a host sysctl

LLVM's ThreadSanitizer aborts with "unexpected memory mapping" on host kernels where `vm.mmap_rnd_bits` is 32. The fix is on the host:

```
sysctl -w vm.mmap_rnd_bits=28
```

A container cannot set this for itself, so this belongs to whoever runs the hosts, and it must be part of host provisioning rather than something discovered per student. `ci-smoke.sh` treats a TSan failure as a **warning**, not an error, for precisely this reason: a failure on a CI runner is a finding about that host, not a defect in the image.

### Each student container needs a distinct host UID

`RLIMIT_NPROC` (`ulimit -u`, which CS 341 teaches) is enforced per **host** UID, not per container. If every student container runs as UID 1000, they share one process budget: one student's fork bomb exhausts it for everyone on that host, and the students who are hit have no way to see why.

The Dockerfiles take `STUDENT_UID` as a build arg defaulting to 1000, but the runtime platform is expected to override the UID per student. If the runtime cannot give distinct UIDs, that is a finding worth writing down before the platform is chosen, not after.

### The fa26 apt pins were removed and must be regenerated

The course's existing pins name 24.04 package versions — clang-18 `1:18.1.3`, valgrind `3.22.0`, libc6-dbg `2.39` — which do not exist in Ubuntu 26.04. Pinning to them with `Pin-Priority: 1001` fails the build outright, so the pins file was removed rather than carried forward broken.

Package names in `cs341/fa26/Dockerfile` are therefore unversioned today. **The first successful build must record the resolved versions**, which then become an `apt_pins` file in that directory. The same applies to `cs341/sp27` against Debian trixie.

Until that happens, two builds a month apart can produce different toolchains from the same Dockerfile — which is the thing pinning exists to prevent. Copy the versions out of the first green build's job summary and commit them.

`cs341/fa26/ci-smoke.sh` currently asserts the old pinned versions (clang 18.1.3, valgrind 3.22.0), so it is expected to fail on 26.04 until both it and the pins are regenerated together.
