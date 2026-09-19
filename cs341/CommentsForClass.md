# CS 341 — System Programming — comments for the instructor

This file is the starting point for a conversation with the instructor about whether CS 341 could run in a Linux container instead of a VM. Everything in it was assembled from public course materials — course sites, public handouts, public repos — and where a course's materials are not public we say so plainly rather than guessing quietly. **Nothing here has been measured yet**: any memory figures are estimates, and the point of the pilot is to replace them with real numbers. Please read it and correct whatever is wrong; the corrections are the reason the file exists.

One note on memory: the number on a VM request form is a *ceiling*, not a reservation. A container's limit works the same way, but because containers only consume what they actually touch, a lower ceiling is usually harmless and lets us fit more students per host. If a suggested limit looks too low for your course, tell us — raising a limit is a one-line change.

**Status:** CS 341 is the active pilot — it is the one class being built today. The real, working image lives in `cs341/fa26/` in this repo; it is the only image here that has actually been built.

- **Pilot class.** The image here is derived from the course's existing grader image (`cs341-illinois/docker-base`), so students and the autograder share a toolchain: Ubuntu 24.04, clang-18, valgrind, strace, gdb, and the course's version pins.
- **Works in a container**, with two caveats. ThreadSanitizer may need a host kernel setting (`vm.mmap_rnd_bits`) that a container cannot set for itself. And the `ulimit -u` behaviour the course teaches is enforced per *host* user ID, so each student's container must run as a distinct UID or they share one process budget — a fork bomb in one would hit others.
- **Would need a real VM:** the Netfilter kernel-module lab, if it returns to the schedule. Kernel modules cannot be loaded from a container.
- **To confirm:** whether the networking/chatroom MPs need students to reach each other's servers directly, and the peak memory of the malloc MP.

**Shared note with CS 340.** Both CS 341 and CS 340 expect students' servers to survive logout. Any "stop idle containers" policy has to understand that, or it will kill work that is waiting for a checkoff.

---

## What we are asking for

For your class, the most useful replies are:

1. **Corrections** to anything above.
2. **The software list** — if there is a setup script, package list or image you already use, that is worth more than any amount of guessing on our part.
3. **What would break** if students had a container instead of a VM: anything needing a reboot, a kernel module, a specific address, a GUI, or an exact machine configuration for grading.
4. **Whether the suggested memory limit is plausible** for your assignments' peak usage.

Corrections are welcome as issues or pull requests against this file, or by email.
