# CS 525 — Advanced Distributed Systems — comments for the instructor

This file is the starting point for a conversation with the instructor about whether CS 525 could run in a Linux container instead of a VM. Everything in it was assembled from public course materials — course sites, public handouts, public repos — and where a course's materials are not public we say so plainly rather than guessing quietly. **Nothing here has been measured yet**: any memory figures are estimates, and the point of the pilot is to replace them with real numbers. Please read it and correct whatever is wrong; the corrections are the reason the file exists.

One note on memory: the number on a VM request form is a *ceiling*, not a reservation. A container's limit works the same way, but because containers only consume what they actually touch, a lower ceiling is usually harmless and lets us fit more students per host. If a suggested limit looks too low for your course, tell us — raising a limit is a one-line change.

**Status:** only CS 341 Fall 2026 is being built today. Everything below is a proposal awaiting your response; no image for this class has been built or run.

- Group research projects, so a shared image can only provide toolchains; each group brings its own stack on top. That works, provided the platform supports Docker and small Kubernetes clusters inside a container.
- **Two honest limitations.** A minority of projects (kernel, eBPF, RDMA) will still need a real VM or CloudLab, and we cannot know which until projects form — so that capacity has to exist all semester. And projects report performance numbers, which are unreliable on shared hosts; dedicated time or CloudLab for final measurements would help.

Draft, never-built files for this class are in this directory: `Dockerfile.suggested` (a research base image groups layer their own stack on) and `docker-compose.yml.suggested` (an example three-node group cluster).

---

## What we are asking for

For your class, the most useful replies are:

1. **Corrections** to anything above.
2. **The software list** — if there is a setup script, package list or image you already use, that is worth more than any amount of guessing on our part.
3. **What would break** if students had a container instead of a VM: anything needing a reboot, a kernel module, a specific address, a GUI, or an exact machine configuration for grading.
4. **Whether the suggested memory limit is plausible** for your assignments' peak usage.

Corrections are welcome as issues or pull requests against this file, or by email.
