# ENG 298 (CYB) and ENG 498 (FSA) — comments for the instructor

This file is the starting point for a conversation with the instructor about whether ENG 298 (CYB) and ENG 498 (FSA) could run in a Linux container instead of a VM. Everything in it was assembled from public course materials — course sites, public handouts, public repos — and where a course's materials are not public we say so plainly rather than guessing quietly. **Nothing here has been measured yet**: any memory figures are estimates, and the point of the pilot is to replace them with real numbers. Please read it and correct whatever is wrong; the corrections are the reason the file exists.

One note on memory: the number on a VM request form is a *ceiling*, not a reservation. A container's limit works the same way, but because containers only consume what they actually touch, a lower ceiling is usually harmless and lets us fit more students per host. If a suggested limit looks too low for your course, tell us — raising a limit is a one-line change.

**Status:** only CS 341 Fall 2026 is being built today. Everything below is a proposal awaiting your response; no image for this class has been built or run.

This file covers both courses, because the same VM request and the same open questions apply to each.

- We could not find syllabi or lab materials for either course, so what runs on these VMs is unknown to us. Everything below is provisional.
- ENG 298 looks like a straightforward fit. ENG 498 FSA needs systemd and service management inside the container, which is supported but requires a specific runtime.
- **A confirmed limit:** FSA's catalogue text covers both Linux *and Windows* systems. Windows cannot run in a Linux container, so that portion needs real machines or the existing vendor platform. Parts of a systems-administration course — kernel modules, real disks, LVM — also cannot be taught inside a container.

A single draft, never-built Dockerfile covering both courses is in `Dockerfile.suggested` in this directory.

---

## What we are asking for

For your class, the most useful replies are:

1. **Corrections** to anything above.
2. **The software list** — if there is a setup script, package list or image you already use, that is worth more than any amount of guessing on our part.
3. **What would break** if students had a container instead of a VM: anything needing a reboot, a kernel module, a specific address, a GUI, or an exact machine configuration for grading.
4. **Whether the suggested memory limit is plausible** for your assignments' peak usage.

Corrections are welcome as issues or pull requests against this file, or by email.
