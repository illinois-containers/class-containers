# CS 461 / ECE 422 — Computer Security I — comments for the instructor

This file is the starting point for a conversation with the instructor about whether CS 461 / ECE 422 could run in a Linux container instead of a VM. Everything in it was assembled from public course materials — course sites, public handouts, public repos — and where a course's materials are not public we say so plainly rather than guessing quietly. **Nothing here has been measured yet**: any memory figures are estimates, and the point of the pilot is to replace them with real numbers. Please read it and correct whatever is wrong; the corrections are the reason the file exists.

One note on memory: the number on a VM request form is a *ceiling*, not a reservation. A container's limit works the same way, but because containers only consume what they actually touch, a lower ceiling is usually harmless and lets us fit more students per host. If a suggested limit looks too low for your course, tell us — raising a limit is a one-line change.

**Status:** only CS 341 Fall 2026 is being built today. Everything below is a proposal awaiting your response; no image for this class has been built or run.

- The crypto and web assignments fit containers cleanly. The exploit and network assignments need specific arrangements: the memory-randomisation setting the handouts disable is machine-wide, so students (and the grader) would use a per-program wrapper instead.
- **The real question is grading.** The course grades against a specific shipped environment and tells students not to substitute their own. A container can only replace it if staff certify it as equivalent — possibly pinning an older Ubuntu for address-exact work.
- As with CS 460, we would not put this course on hosts shared with other classes.

A draft, never-built Dockerfile for this class is in `Dockerfile.suggested` in this directory.

---

## What we are asking for

For your class, the most useful replies are:

1. **Corrections** to anything above.
2. **The software list** — if there is a setup script, package list or image you already use, that is worth more than any amount of guessing on our part.
3. **What would break** if students had a container instead of a VM: anything needing a reboot, a kernel module, a specific address, a GUI, or an exact machine configuration for grading.
4. **Whether the suggested memory limit is plausible** for your assignments' peak usage.

Corrections are welcome as issues or pull requests against this file, or by email.
