# CS 460 / ECE 419 — Security Laboratory — comments for the instructor

This file is the starting point for a conversation with the instructor about whether CS 460 / ECE 419 could run in a Linux container instead of a VM. Everything in it was assembled from public course materials — course sites, public handouts, public repos — and where a course's materials are not public we say so plainly rather than guessing quietly. **Nothing here has been measured yet**: any memory figures are estimates, and the point of the pilot is to replace them with real numbers. Please read it and correct whatever is wrong; the corrections are the reason the file exists.

One note on memory: the number on a VM request form is a *ceiling*, not a reservation. A container's limit works the same way, but because containers only consume what they actually touch, a lower ceiling is usually harmless and lets us fit more students per host. If a suggested limit looks too low for your course, tell us — raising a limit is a one-line change.

**Status:** only CS 341 Fall 2026 is being built today. Everything below is a proposal awaiting your response; no image for this class has been built or run.

- We could not determine what currently runs on these VMs — the recent syllabi we found describe a vendor-hosted lab platform, and no 2025–26 lab materials are public. **Your input would change more here than anywhere else in this project.**
- The industrial-control lab in the public `uiuc-turbine` repo already runs as Docker containers, which is encouraging, though it would need rework to run safely on shared hardware.
- **Two hard limits:** the Windows portion cannot run in a Linux container and would need a small pool of real machines. And because students run attack tooling and gain root inside their own container by design, we would keep this course on separate hosts from other classes, or on lightweight VMs.

A draft, never-built Dockerfile for this class is in `Dockerfile.suggested` in this directory. Given how little we could confirm, treat it as a conversation starter rather than a proposal.

---

## What we are asking for

For your class, the most useful replies are:

1. **Corrections** to anything above.
2. **The software list** — if there is a setup script, package list or image you already use, that is worth more than any amount of guessing on our part.
3. **What would break** if students had a container instead of a VM: anything needing a reboot, a kernel module, a specific address, a GUI, or an exact machine configuration for grading.
4. **Whether the suggested memory limit is plausible** for your assignments' peak usage.

Corrections are welcome as issues or pull requests against this file, or by email.
