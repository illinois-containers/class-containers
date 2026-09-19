# bigtest: measuring what a class actually costs

Each offering may carry two test scripts:

| | `ci-smoke.sh` | `bigtest.sh` |
|---|---|---|
| Runs in | seconds | minutes to an hour |
| Asks | do the tools exist and work? | does a course-scale workload work, and what does it cost? |
| Run by | CI, on every build | instructors, and whoever runs the hosts |
| Output | pass/fail | pass/fail **plus measurements** |

`bigtest.sh` exists because every memory figure in this project started as an estimate read off a course website. This is how those become numbers. If you only run one thing before sizing hardware, run this.

## The contract

A class's `bigtest.sh` must:

- accept `--level quick|full` (quick ≈ 2–5 min for CI; full is the real workload), `--json <path>`, and `--jobs N`
- **derive its parallelism from `cpu.max`, not `nproc`** — inside a container `nproc` reports the *host's* CPU count, and `make -j$(nproc)` under a CPU quota is the likeliest way to blow the memory limit
- measure peak memory by sampling the cgroup (`/sys/fs/cgroup/memory.current`), not by requiring `/usr/bin/time`, which these images do not install
- report OOM kills from `memory.events`, and print the limits it ran under
- exit 0 on success, otherwise the number of failed phases
- finish by printing `peak across phases: N MB` and a suggested `--memory`, so the farm harness can parse it

The JSON is per-phase — name, status, seconds, peak MB, OOM kills — plus the limits the run saw. Keep phase names stable across semesters so numbers stay comparable year to year.

## What a good bigtest exercises

Not "is clang installed" — that is the smoke test. It should run the things a container plausibly breaks, at the scale the course actually reaches:

- **the heaviest build the course requires**, at realistic parallelism
- **the tools that need kernel cooperation**: sanitizers (ThreadSanitizer's shadow mapping vs the host's `vm.mmap_rnd_bits`), valgrind, gdb, `perf`
- **the resource limits as a feature**: a fork storm should be *contained* by the pids limit and the container should survive — that is a pass, not a failure
- **whatever the course's own workload is**: for CS 423 that means compiling a kernel and booting it under QEMU (with and without `/dev/kvm`, timing both); for CS 426, the MP4 LLVM build under the intended cap; for CS 425, a group of nodes talking to each other; for CS 411, all three databases under load at once
- **disk**, if the class writes a lot

A phase that is slow is fine. A phase that is slow *and unmeasured* is not.

## Running it

Inside a container, with the limits you intend to impose:

```
docker run --rm --memory=2g --pids-limit=512 --cpus=4 \
  -v "$PWD/cs341/fa26/bigtest.sh:/bigtest.sh:ro" \
  ghcr.io/illinois-containers/fa26-cs341-img1 bash /bigtest.sh --level full
```

If it reports OOM kills, the limit is too low for that workload — raise it and note the real figure in the class's `CommentsForClass.md`.

## Running it at farm scale

`scripts/farm-loadtest.sh` runs many containers of the same image simultaneously and reports how many fit:

```
scripts/farm-loadtest.sh --image ghcr.io/illinois-containers/fa26-cs341-img1 \
  --bigtest cs341/fa26/bigtest.sh --count 20 --memory 2g --pids 512 --cpus 2
```

Every container runs at once on purpose: that is deadline night, not an average Tuesday. Each gets a distinct UID, because `RLIMIT_NPROC` is enforced per host UID — if students share one, they share one process budget and one student's fork bomb takes out the others. If your runtime cannot give them distinct UIDs, that is a finding worth writing down.

On Kubernetes the same test is a Job with `completions` and `parallelism` set to the container count, the same values as resource limits, and the JSON collected from each pod's logs. Run it on the hardware you intend to use, not on a laptop.

## Reading the result

- **Containers failing only at high counts** — host pressure, not the image.
- **OOM kills** — the class's memory cap is wrong.
- **Wall time rising faster than the container count** — CPU oversubscription. The classes whose grades depend on measurements (CS 598APE, CS 433, CS 525) cannot share a host in that state.
- **The density figure** the harness prints is an upper bound: it ignores page cache, the orchestrator, and the fact that students are not synchronised. Halve it before believing it.
