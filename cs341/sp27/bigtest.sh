#!/usr/bin/env bash
# CS 341 Spring 2027 — bigtest: heavyweight exercise of this image.
#
# Unlike ci-smoke.sh (seconds, "do the tools exist and basically work"), this
# runs course-scale workloads and MEASURES them. It exists because every memory
# figure in this project is currently an estimate; this is how they become data.
#
# Two audiences:
#   instructor  — does a real MP-sized workload actually work in a container?
#   farm operator — what does one student cost on this hardware, and what
#                   happens at the limits? Feed the JSON to scripts/farm-loadtest.sh
#                   to get containers-per-host.
#
# Usage (inside the container):
#   ./bigtest.sh [--level quick|full] [--json /tmp/bigtest.json] [--jobs N]
#     quick  ~2-4 min, for CI and sanity
#     full   ~15-30 min, the real thing (default)
#
# Typical invocation from the host, with the limits you intend to impose:
#   docker run --rm --memory=2g --pids-limit=512 --cpus=4 \
#     -v "$PWD/cs341/sp27/bigtest.sh:/bigtest.sh:ro" \
#     ghcr.io/illinois-containers/cs341:sp27-img1 bash /bigtest.sh --level full
#
# Exit code 0 = every phase passed. Non-zero = number of failed phases.
# A phase that is *expected* to hit a limit (fork storm) passes when the limit
# contains it cleanly.
set -uo pipefail

LEVEL=full
JSON_OUT=""
JOBS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --level) LEVEL="${2:-full}"; shift 2 ;;
    --json)  JSON_OUT="${2:-}"; shift 2 ;;
    --jobs)  JOBS="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- environment
CG=/sys/fs/cgroup
read_cg() { [ -r "$CG/$1" ] && tr -d '\n' < "$CG/$1" || echo "n/a"; }
MEM_MAX=$(read_cg memory.max)
PIDS_MAX=$(read_cg pids.max)
CPU_MAX=$(read_cg cpu.max)
NPROC_SEEN=$(nproc)
# nproc reports the HOST cpu count unless --cpuset-cpus is set, so derive the
# real parallelism from cpu.max when it is available. `make -j$(nproc)` under a
# --cpus quota is the single likeliest cause of an OOM in these images.
if [ -z "$JOBS" ]; then
  if [ "$CPU_MAX" != "n/a" ] && [ "${CPU_MAX%% *}" != "max" ]; then
    quota=${CPU_MAX%% *}; period=${CPU_MAX##* }
    JOBS=$(( quota / period )); [ "$JOBS" -lt 1 ] && JOBS=1
  else
    JOBS=$NPROC_SEEN
  fi
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

# ------------------------------------------------------------ peak RSS sampler
# No dependency on /usr/bin/time (the `time` package is not installed in these
# images). Sample the cgroup's current usage instead; works under cgroup v2.
PEAKFILE="$WORK/.peak"
sampler_start() {
  echo 0 > "$PEAKFILE"
  ( peak=0
    while :; do
      cur=$(cat "$CG/memory.current" 2>/dev/null || echo 0)
      [ "$cur" -gt "$peak" ] 2>/dev/null && { peak=$cur; echo "$peak" > "$PEAKFILE"; }
      sleep 0.25
    done ) & SAMPLER_PID=$!
}
sampler_reset() { echo 0 > "$PEAKFILE"; }
sampler_peak_mb() { awk '{printf "%.0f", $1/1048576}' "$PEAKFILE" 2>/dev/null || echo 0; }
sampler_stop() { [ -n "${SAMPLER_PID:-}" ] && kill "$SAMPLER_PID" 2>/dev/null; }
oom_count() { awk '/^oom_kill /{print $2}' "$CG/memory.events" 2>/dev/null || echo 0; }

[ -r "$CG/memory.current" ] && sampler_start || echo "note: cgroup memory.current unreadable; peak RSS will report 0"
trap 'sampler_stop; rm -rf "$WORK"' EXIT

# ------------------------------------------------------------------- reporting
FAILS=0
RESULTS=()
phase() {  # phase <name> <command...>
  local name="$1"; shift
  sampler_reset
  local oom_before; oom_before=$(oom_count)
  local start; start=$(date +%s)
  local status="pass" detail=""
  if ! detail=$("$@" 2>&1); then status="fail"; FAILS=$((FAILS + 1)); fi
  local end; end=$(date +%s)
  local peak; peak=$(sampler_peak_mb)
  local oom_after; oom_after=$(oom_count)
  local oomd=$(( ${oom_after:-0} - ${oom_before:-0} ))
  printf '%-26s %-5s %5ss  peak %6s MB  oom %s\n' "$name" "$status" "$((end - start))" "$peak" "$oomd"
  [ -n "$detail" ] && printf '%s\n' "$detail" | sed 's/^/    /'
  RESULTS+=("{\"phase\":\"$name\",\"status\":\"$status\",\"seconds\":$((end - start)),\"peak_mb\":$peak,\"oom_kills\":$oomd}")
}

echo "=============================================================="
echo " CS 341 sp27 bigtest — level=$LEVEL jobs=$JOBS"
echo " memory.max=$MEM_MAX  pids.max=$PIDS_MAX  cpu.max=$CPU_MAX  nproc=$NPROC_SEEN"
echo " $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")  $(clang --version | head -1)"
echo "=============================================================="

# ---------------------------------------------------------------- the workload
if [ "$LEVEL" = quick ]; then NFILES=40; ALLOC_MB=128; THREADS=16; VG_MB=32; else NFILES=300; ALLOC_MB=768; THREADS=64; VG_MB=192; fi

p_parallel_build() {
  mkdir -p build && cd build || return 1
  for i in $(seq 1 "$NFILES"); do
    cat > "m$i.c" <<EOF
#include <stdio.h>
#include <string.h>
static char buf[4096];
int f$i(int x) { memset(buf, x & 0xff, sizeof buf); return (int)strlen(buf) + x; }
EOF
  done
  { echo "int main(void){int t=0;"; for i in $(seq 1 "$NFILES"); do echo "extern int f$i(int); t+=f$i($i);"; done; echo "return t!=0;}"; } > main.c
  make -s -j"$JOBS" -f - <<'MK' >/dev/null || return 1
SRCS := $(wildcard m*.c) main.c
OBJS := $(SRCS:.c=.o)
all: prog
%.o: %.c
	clang -O1 -c $< -o $@
prog: $(OBJS)
	clang $(OBJS) -o prog
MK
  ./prog; cd .. || return 1
}

p_malloc_stress() {
  cat > alloc.c <<EOF
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#define MB ${ALLOC_MB}
int main(void) {
  /* mixed sizes, interleaved frees: the pattern the malloc MP exercises */
  size_t n = 20000; void **p = calloc(n, sizeof *p);
  for (size_t i = 0; i < n; i++) { size_t sz = (i % 97 + 1) * 1024; p[i] = malloc(sz); if (p[i]) memset(p[i], 1, sz); }
  for (size_t i = 0; i < n; i += 2) { free(p[i]); p[i] = NULL; }
  char *big = malloc((size_t)MB * 1024 * 1024);
  if (!big) { fprintf(stderr, "large malloc failed\n"); return 1; }
  memset(big, 2, (size_t)MB * 1024 * 1024);
  for (size_t i = 1; i < n; i += 2) free(p[i]);
  free(big); free(p); printf("malloc stress ok\n"); return 0;
}
EOF
  clang -O1 -o alloc alloc.c && ./alloc
}

p_asan_workload() {
  clang -fsanitize=address -O1 -g -o alloc_asan alloc.c || return 1
  ASAN_OPTIONS=detect_leaks=1 ./alloc_asan
}

p_tsan_threads() {
  cat > threads.c <<EOF
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#define NT ${THREADS}
static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static long counter;
static void *w(void *a) { (void)a; for (int i = 0; i < 20000; i++) { pthread_mutex_lock(&m); counter++; pthread_mutex_unlock(&m); } return 0; }
int main(void) {
  pthread_t t[NT];
  for (int i = 0; i < NT; i++) if (pthread_create(&t[i], 0, w, 0)) { perror("pthread_create"); return 1; }
  for (int i = 0; i < NT; i++) pthread_join(t[i], 0);
  printf("counter=%ld (expect %d)\n", counter, NT * 20000);
  return counter != (long)NT * 20000;
}
EOF
  clang -fsanitize=thread -O1 -g -o threads_tsan threads.c 2>tsan_build.txt || { echo "TSan build failed (runtime package missing?): $(head -2 tsan_build.txt)"; return 1; }
  ./threads_tsan > tsan_run.txt 2>&1 || { grep -qi "unable to mmap\|FATAL" tsan_run.txt && echo "TSan could not start — host likely needs vm.mmap_rnd_bits=28"; cat tsan_run.txt; return 1; }
  cat tsan_run.txt
}

p_valgrind() {
  cat > vgmem.c <<EOF
#include <stdlib.h>
#include <string.h>
int main(void) { size_t n = (size_t)${VG_MB} * 1024 * 1024; char *p = malloc(n); if (!p) return 1; memset(p, 3, n); free(p); return 0; }
EOF
  clang -O0 -g -o vgmem vgmem.c || return 1
  valgrind --error-exitcode=9 --leak-check=full --quiet ./vgmem
}

p_fork_containment() {
  # Spawns processes until the pids limit stops it. PASSES when the limit
  # contains the storm and the shell survives — that is the property a farm
  # operator needs, and the reason each student needs a distinct host UID.
  cat > forkstorm.c <<'EOF'
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
int main(void) {
  int made = 0;
  for (int i = 0; i < 100000; i++) { pid_t p = fork(); if (p < 0) break; if (p == 0) { pause(); _exit(0); } made++; }
  printf("forked %d children before the limit stopped us\n", made);
  kill(0, SIGTERM);
  while (waitpid(-1, 0, WNOHANG) > 0) {}
  return 0;
}
EOF
  clang -o forkstorm forkstorm.c || return 1
  ( ./forkstorm ) ; sleep 1
  echo "shell still alive after fork storm: $(id -u) $(ls /proc/self >/dev/null && echo yes)"
}

p_sockets() {
  cat > srv.py <<'EOF'
import socket, threading, sys
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0)); srv.listen(64); port = srv.getsockname()[1]
print(port, flush=True)
def serve():
    for _ in range(64):
        c, _a = srv.accept()
        d = c.recv(65536); c.sendall(d); c.close()
threading.Thread(target=serve, daemon=True).start()
sys.stdin.readline()
EOF
  exec 3< <(python3 srv.py); read -r PORT <&3
  python3 - "$PORT" <<'EOF'
import socket, sys
port = int(sys.argv[1]); payload = b"x" * 65536; ok = 0
for _ in range(64):
    s = socket.create_connection(("127.0.0.1", port)); s.sendall(payload)
    if s.recv(65536): ok += 1
    s.close()
print(f"{ok}/64 loopback round-trips ok")
sys.exit(0 if ok == 64 else 1)
EOF
}

p_disk() {
  dd if=/dev/zero of=bigfile bs=1M count=$([ "$LEVEL" = quick ] && echo 128 || echo 1024) 2>&1 | tail -1
  sync; du -sh bigfile; rm -f bigfile
}

phase "parallel-build"      p_parallel_build
phase "malloc-stress"       p_malloc_stress
phase "asan-workload"       p_asan_workload
phase "tsan-threads"        p_tsan_threads
phase "valgrind-heavy"      p_valgrind
phase "fork-containment"    p_fork_containment
phase "sockets-loopback"    p_sockets
phase "disk-throughput"     p_disk

# ---------------------------------------------------------------------- report
OVERALL_PEAK=$(printf '%s\n' "${RESULTS[@]}" | sed -n 's/.*"peak_mb":\([0-9]*\).*/\1/p' | sort -n | tail -1)
SUGGEST=$(( (OVERALL_PEAK * 13 / 10 + 63) / 64 * 64 ))   # peak + 30%, rounded up to 64 MB
echo "--------------------------------------------------------------"
echo "peak across phases: ${OVERALL_PEAK} MB"
echo "suggested --memory for this workload: ${SUGGEST}m  (peak + 30% headroom)"
echo "phases failed: $FAILS"
[ "$(oom_count)" != "0" ] && echo "WARNING: the cgroup recorded OOM kills — the memory limit was too low for this workload"

if [ -n "$JSON_OUT" ]; then
  { echo "{"
    echo "  \"class\": \"cs341\", \"semester\": \"sp27\", \"level\": \"$LEVEL\","
    echo "  \"limits\": {\"memory_max\": \"$MEM_MAX\", \"pids_max\": \"$PIDS_MAX\", \"cpu_max\": \"$CPU_MAX\", \"nproc_seen\": $NPROC_SEEN, \"jobs\": $JOBS},"
    echo "  \"peak_mb\": ${OVERALL_PEAK:-0}, \"suggested_memory_mb\": $SUGGEST, \"failed_phases\": $FAILS,"
    echo "  \"phases\": [$(IFS=,; echo "${RESULTS[*]}")]"
    echo "}"; } > "$JSON_OUT"
  echo "wrote $JSON_OUT"
fi

exit "$FAILS"
