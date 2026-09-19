#!/usr/bin/env bash
# Smoke test for the CS 341 Spring 2027 image. Runs inside the built image in
# CI, and can be run by hand:
#   docker run --rm -v "$PWD/cs341/sp27/ci-smoke.sh:/smoke.sh:ro" <image> bash /smoke.sh
#
# Checks that the tools exist AND that the things containers usually break
# still work. Must stay quick (target: under 30s).
set -uo pipefail

fails=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

echo "== versions (record these; they are the de facto pins until apt_pins exists)"
for t in clang gcc gdb valgrind strace python3 git; do
  if have "$t"; then
    printf '  %-9s %s\n' "$t" "$("$t" --version 2>&1 | head -1)"
  else
    fail "$t not installed"
  fi
done
printf '  %-9s %s\n' "libc" "$(ldd --version 2>&1 | head -1)"

echo "== compile and run"
cat > hello.c <<'EOF'
#include <stdio.h>
int main(void) { printf("hello\n"); return 0; }
EOF
if clang -Wall -Werror -o hello hello.c 2>err.txt && [ "$(./hello)" = "hello" ]; then
  pass "clang compiles and runs a C program"
else
  fail "clang compile/run: $(head -3 err.txt)"
fi

echo "== sanitizers (the runtime may live in a separate Debian package)"
cat > leak.c <<'EOF'
#include <stdlib.h>
int main(void) { char *p = malloc(32); p[0] = 1; return 0; }
EOF
if clang -fsanitize=address -g -o leak_asan leak.c 2>asan_build.txt; then
  if ASAN_OPTIONS=detect_leaks=1 ./leak_asan 2>asan_run.txt; then
    if [ "$(uname -m)" = "aarch64" ]; then
      # Confirmed on arm64 (2026-09-19): the same image reports this leak
      # correctly on amd64. Known limitation, not a regression — and the
      # reason arm64 images are dev-only. See Known-Issues.md.
      printf '  KNOWN  LeakSanitizer reports nothing on arm64 — dev images only, never grading\n'
    else
      fail "AddressSanitizer did not report the leak (leak detection off?)"
    fi
  else
    grep -q "LeakSanitizer\|detected memory leaks" asan_run.txt \
      && pass "AddressSanitizer detects a leak" \
      || fail "ASan ran but produced no leak report"
  fi
else
  fail "ASan build failed — install the clang runtime package: $(head -2 asan_build.txt)"
fi

cat > race.c <<'EOF'
#include <pthread.h>
static int shared;
static void *worker(void *arg) { (void)arg; for (int i = 0; i < 1000; i++) shared++; return 0; }
int main(void) {
  pthread_t a, b;
  pthread_create(&a, 0, worker, 0); pthread_create(&b, 0, worker, 0);
  pthread_join(a, 0); pthread_join(b, 0);
  return 0;
}
EOF
if clang -fsanitize=thread -g -o race_tsan race.c 2>tsan_build.txt; then
  ./race_tsan >/dev/null 2>tsan_run.txt
  if grep -q "WARNING: ThreadSanitizer" tsan_run.txt; then
    pass "ThreadSanitizer detects a data race"
  elif grep -qi "unable to mmap\|FATAL" tsan_run.txt; then
    # The classic container failure: TSan's shadow mapping vs the host's
    # vm.mmap_rnd_bits. Not fixable from inside the image.
    fail "TSan could not start — host likely needs vm.mmap_rnd_bits=28: $(head -2 tsan_run.txt)"
  else
    fail "TSan ran but reported no race"
  fi
else
  fail "TSan build failed — install the clang runtime package: $(head -2 tsan_build.txt)"
fi

echo "== valgrind"
if valgrind --error-exitcode=42 --leak-check=full ./hello >/dev/null 2>vg.txt; then
  pass "valgrind runs a binary cleanly"
else
  fail "valgrind failed: $(head -3 vg.txt)"
fi

echo "== gdb (needs SYS_PTRACE when attaching to a running process; this only"
echo "   launches, which works unprivileged)"
if gdb -batch -ex run -ex quit ./hello 2>gdb.txt | grep -q hello; then
  pass "gdb launches and runs a program"
else
  fail "gdb failed: $(head -3 gdb.txt)"
fi

echo "== fork/exec and pipes"
cat > fork.c <<'EOF'
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>
int main(void) {
  pid_t p = fork();
  if (p == 0) { _exit(7); }
  int st; waitpid(p, &st, 0);
  printf("%d\n", WEXITSTATUS(st));
  return 0;
}
EOF
if clang -o forktest fork.c 2>/dev/null && [ "$(./forktest)" = "7" ]; then
  pass "fork/waitpid works"
else
  fail "fork/waitpid test failed"
fi

echo "== container-specific sanity"
nproc_seen="$(nproc)"
echo "  note  nproc reports ${nproc_seen} — this is the HOST cpu count unless"
echo "        the platform sets --cpuset-cpus; 'make -j\$(nproc)' can overcommit"
[ "$(id -u)" != "0" ] && pass "running as non-root (uid $(id -u))" || fail "running as root"

echo
if [ "$fails" -eq 0 ]; then
  echo "SMOKE OK"
else
  echo "SMOKE FAILED: $fails check(s)"
fi
exit "$fails"
