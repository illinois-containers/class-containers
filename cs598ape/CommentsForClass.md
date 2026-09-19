# CS 598 APE — Performance Engineering — comments for the instructor

This file is the starting point for a conversation with the instructor about whether CS 598 APE could run in a Linux container instead of a VM. Everything in it was assembled from public course materials — course sites, public handouts, public repos — and where a course's materials are not public we say so plainly rather than guessing quietly. **Nothing here has been measured yet**: any memory figures are estimates, and the point of the pilot is to replace them with real numbers. Please read it and correct whatever is wrong; the corrections are the reason the file exists.

One note on memory: the number on a VM request form is a *ceiling*, not a reservation. A container's limit works the same way, but because containers only consume what they actually touch, a lower ceiling is usually harmless and lets us fit more students per host. If a suggested limit looks too low for your course, tell us — raising a limit is a one-line change.

**Status:** only CS 341 Fall 2026 is being built today. Everything below is a proposal awaiting your response; no image for this class has been built or run.

- The course already publishes its own Docker image, so packaging is mostly solved.
- **The difficulty is measurement, not packaging.** Grades depend on reported speedups, and shared hosts distort timing badly enough that a correct optimisation can appear to make things slower. Doing this properly needs dedicated physical cores, access to hardware performance counters, and ideally bookable exclusive time near deadlines.
- **A possible upside:** virtual machines usually expose no hardware performance counters at all, so containers on bare metal could be *better* for this course than today's VMs. Worth testing.
- **The key question:** do the assignments actually need hardware counters, or is wall-clock timing enough? That one answer decides how much of the above is required.

A draft, never-built Dockerfile for this class is in `Dockerfile.suggested` in this directory.

---

## What we are asking for

For your class, the most useful replies are:

1. **Corrections** to anything above.
2. **The software list** — if there is a setup script, package list or image you already use, that is worth more than any amount of guessing on our part.
3. **What would break** if students had a container instead of a VM: anything needing a reboot, a kernel module, a specific address, a GUI, or an exact machine configuration for grading.
4. **Whether the suggested memory limit is plausible** for your assignments' peak usage.

Corrections are welcome as issues or pull requests against this file, or by email.
