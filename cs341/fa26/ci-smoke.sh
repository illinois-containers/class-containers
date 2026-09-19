#!/usr/bin/env bash
# Smoke test for the cs341 student image (see cs341/testplan.md, section 2).
# Runs inside the freshly built container as: bash /ci-smoke.sh
# Checks the grader-pinned tool versions (rows 1, 8, 10) plus a tiny
# compile-and-run (rows 2-3). Budget: well under 30 seconds.
# Version mismatches and compile failures exit non-zero and fail the CI job.
# The ThreadSanitizer check (row 4) is a WARNING only: LLVM 18 TSan aborts with
# "unexpected memory mapping" on host kernels where vm.mmap_rnd_bits=32, and
# that sysctl cannot be changed from inside a container (testplan section 0.1),
# so a CI-runner failure there is a host finding, not an image defect.

set -euo pipefail

pass() { echo "smoke: PASS - $*"; }
warn() { echo "smoke: WARN - $*"; }
fail() { echo "smoke: FAIL - $*" >&2; exit 1; }

clang_ver="$(clang -dumpversion)"
case "$clang_ver" in
  18.1.3) pass "clang $clang_ver matches the grader pin (1:18.1.3-1ubuntu1)" ;;
  18.*)   warn "clang $clang_ver is 18.x but not the pinned 18.1.3 - grader parity drift" ;;
  *)      fail "clang $clang_ver - expected 18.1.3 per the apt pin" ;;
esac

valgrind_ver="$(valgrind --version)"
case "$valgrind_ver" in
  valgrind-3.22.0) pass "$valgrind_ver matches the grader pin (1:3.22.0-0ubuntu2)" ;;
  valgrind-3.22*)  warn "$valgrind_ver is 3.22.x but not the pinned 3.22.0" ;;
  *)               fail "$valgrind_ver - expected 3.22.0 per the apt pin" ;;
esac

strace_ver="$(strace --version | head -1)"
case "$strace_ver" in
  *6.8*) pass "strace reports $strace_ver (pin 6.8-0ubuntu2)" ;;
  *)     fail "strace version unexpected: $strace_ver - expected 6.8 per the apt pin" ;;
esac

cat > /tmp/a.c <<'EOF'
#include <stdio.h>
int main(void) { puts("c-ok"); return 0; }
EOF
clang -Wall -Werror -std=c99 /tmp/a.c -o /tmp/a
out="$(/tmp/a)"
[ "$out" = "c-ok" ] || fail "compiled binary printed '$out', expected 'c-ok'"
pass "clang compile-and-run (testplan section 2, row 2)"

cat > /tmp/t.c <<'EOF'
#include <pthread.h>
#include <stdio.h>
static void *f(void *_) { (void)_; puts("thr-ok"); return 0; }
int main(void) {
  pthread_t t;
  pthread_create(&t, 0, f, 0);
  pthread_join(t, 0);
  return 0;
}
EOF
clang -pthread /tmp/t.c -o /tmp/t
out="$(/tmp/t)"
[ "$out" = "thr-ok" ] || fail "pthread binary printed '$out', expected 'thr-ok'"
pass "pthreads link and run (testplan section 2, row 3)"

vout="$(valgrind -q --error-exitcode=9 /tmp/a 2>&1)" || fail "valgrind run failed: $vout"
pass "valgrind clean run on the test binary (testplan section 2, row 8)"

clang -fsanitize=thread -g -pthread /tmp/t.c -o /tmp/t_tsan
if tout="$(timeout 10 /tmp/t_tsan 2>&1)"; then
  pass "ThreadSanitizer runs on this host kernel (testplan section 2, row 4)"
else
  warn "TSan did not run cleanly; output follows. If it says 'unexpected memory mapping',"
  warn "the HOST needs sysctl vm.mmap_rnd_bits=28 - a container cannot set it (testplan section 0.1)."
  printf '%s\n' "$tout" | sed 's/^/  /'
fi

echo "smoke: cs341 image OK (${SECONDS}s)"
