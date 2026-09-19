#!/usr/bin/env bash
# farm-loadtest.sh — run many students' worth of bigtest.sh at once and report
# what one host can actually carry.
#
# The per-class bigtest.sh answers "what does ONE student cost?". This answers
# the question a farm operator actually has: "how many of them fit, and what
# breaks first?" — the number this whole project has been estimating rather
# than measuring.
#
# Usage:
#   scripts/farm-loadtest.sh --image ghcr.io/illinois-containers/cs341:fa26-img1 \
#                            --bigtest cs341/fa26/bigtest.sh \
#                            --count 20 --memory 2g --pids 512 --cpus 2 [--level quick]
#
# Every container runs the same workload simultaneously, which is the deadline
# case — not the average case. Run it on the hardware you intend to buy or
# reuse, not on a laptop.
#
# Kubernetes: the same idea is a Job with completions=N, parallelism=N, the
# limits below as resource limits, and the JSON collected from each pod's logs.
# See docs/BIGTEST.md.
set -uo pipefail

IMAGE=""; BIGTEST=""; COUNT=10; MEMORY=2g; PIDS=512; CPUS=2; LEVEL=quick; RUNTIME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --bigtest) BIGTEST="$2"; shift 2 ;;
    --count) COUNT="$2"; shift 2 ;;
    --memory) MEMORY="$2"; shift 2 ;;
    --pids) PIDS="$2"; shift 2 ;;
    --cpus) CPUS="$2"; shift 2 ;;
    --level) LEVEL="$2"; shift 2 ;;
    --runtime) RUNTIME="$2"; shift 2 ;;    # e.g. sysbox-runc, runsc
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$IMAGE" ] && [ -n "$BIGTEST" ] || { echo "--image and --bigtest are required" >&2; exit 2; }
[ -r "$BIGTEST" ] || { echo "cannot read $BIGTEST" >&2; exit 2; }
command -v docker >/dev/null || { echo "docker not found" >&2; exit 2; }

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
STAMP=$(date +%Y%m%d-%H%M%S)
NAME_PREFIX="loadtest-$STAMP"

host_mem_gb() {
  if [ -r /proc/meminfo ]; then awk '/MemTotal/{printf "%.1f", $2/1048576}' /proc/meminfo
  else sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1f", $1/1073741824}'; fi
}

echo "=============================================================="
echo " farm load test — $COUNT concurrent containers"
echo " image:   $IMAGE"
echo " limits:  --memory=$MEMORY --pids-limit=$PIDS --cpus=$CPUS ${RUNTIME:+--runtime=$RUNTIME}"
echo " host:    $(uname -sr), $(host_mem_gb) GB RAM, $(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc) cpus"
echo " started: $(date -u +%FT%TZ)"
echo "=============================================================="

START=$(date +%s)
for i in $(seq 1 "$COUNT"); do
  # Each container gets its own UID, as the real platform must: RLIMIT_NPROC is
  # enforced per host UID, so sharing one UID would pool every student's
  # process budget. If this fails on your runtime, that is a finding.
  uid=$((20000 + i))
  # NOT --rm: the containers must survive exit so their logs and JSON can be
  # collected below. They are removed explicitly at the end.
  docker run -d --name "${NAME_PREFIX}-$i" \
    ${RUNTIME:+--runtime="$RUNTIME"} \
    --memory="$MEMORY" --memory-swap="$MEMORY" --pids-limit="$PIDS" --cpus="$CPUS" \
    --user "$uid:$uid" \
    -v "$(cd "$(dirname "$BIGTEST")" && pwd)/$(basename "$BIGTEST")":/bigtest.sh:ro \
    "$IMAGE" bash /bigtest.sh --level "$LEVEL" --json /tmp/report.json >/dev/null \
    || echo "container $i failed to start"
done

echo "all containers launched; waiting..."
while docker ps --format '{{.Names}}' | grep -q "^${NAME_PREFIX}-"; do sleep 5; done
END=$(date +%s)

ok=0; failed=0; peaks=""
for i in $(seq 1 "$COUNT"); do
  log="$OUT/$i.log"
  docker logs "${NAME_PREFIX}-$i" > "$log" 2>&1 || true
  docker cp "${NAME_PREFIX}-$i:/tmp/report.json" "$OUT/$i.json" 2>/dev/null || true
  code=$(docker inspect -f '{{.State.ExitCode}}' "${NAME_PREFIX}-$i" 2>/dev/null || echo 1)
  oomkilled=$(docker inspect -f '{{.State.OOMKilled}}' "${NAME_PREFIX}-$i" 2>/dev/null || echo unknown)
  if [ "$code" = "0" ]; then ok=$((ok + 1)); else failed=$((failed + 1)); echo "  container $i exited $code (OOMKilled=$oomkilled)"; fi
  p=$(sed -n 's/^peak across phases: \([0-9]*\) MB/\1/p' "$log" 2>/dev/null | tail -1)
  [ -n "$p" ] && peaks="$peaks$p\n"
  docker rm -f "${NAME_PREFIX}-$i" >/dev/null 2>&1 || true
done

echo "--------------------------------------------------------------"
echo "wall time:        $((END - START))s"
echo "containers ok:    $ok / $COUNT   (failed: $failed)"
if [ -n "$peaks" ]; then
  stats=$(printf "$peaks" | sort -n | awk '{a[NR]=$1} END {printf "%d %d %d", a[1], a[int(NR/2)+1], a[NR]}')
  set -- $stats
  echo "peak RSS per container: min ${1} MB, median ${2} MB, max ${3} MB"
  hostgb=$(host_mem_gb)
  echo "at the median, one ${hostgb} GB host holds roughly $(awk -v h="$hostgb" -v m="${2:-1}" 'BEGIN{printf "%d", (h*1024*0.85)/m}') containers"
  echo "  (85% of host RAM, ignoring the kernel's page cache and the orchestrator;"
  echo "   treat it as an upper bound and confirm with a longer run)"
else
  echo "no peak figures parsed — check $OUT/*.log"
fi
echo
echo "What to look at when this goes wrong:"
echo "  * containers failing only at high --count  -> host pressure, not the image"
echo "  * 'OOM kills' in a log                     -> --memory too low for this class"
echo "  * TSan mmap failures                       -> host needs vm.mmap_rnd_bits=28"
echo "  * fork-containment failing                 -> pids limit or shared UIDs"
echo "  * wall time growing faster than --count    -> CPU oversubscription; the"
echo "    measurement-sensitive classes (CS 598APE, CS 433, CS 525) cannot live here"
echo "logs: $OUT (copy them out before this script exits)"
