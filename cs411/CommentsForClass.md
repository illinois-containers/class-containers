# CS 411 — Database Systems — comments for the instructor

This file is the starting point for a conversation with the instructor about whether CS 411 could run in a Linux container instead of a VM. Everything in it was assembled from public course materials — course sites, public handouts, public repos — and where a course's materials are not public we say so plainly rather than guessing quietly. **Nothing here has been measured yet**: any memory figures are estimates, and the point of the pilot is to replace them with real numbers. Please read it and correct whatever is wrong; the corrections are the reason the file exists.

One note on memory: the number on a VM request form is a *ceiling*, not a reservation. A container's limit works the same way, but because containers only consume what they actually touch, a lower ceiling is usually harmless and lets us fit more students per host. If a suggested limit looks too low for your course, tell us — raising a limit is a one-line change.

**Status:** only CS 341 Fall 2026 is being built today. Everything below is a proposal awaiting your response; no image for this class has been built or run.

**Please read this one with extra scepticism.** Our notes on CS 411 are thinner than for most classes: much of the course's material is not public, so what follows is largely inference from the parts we could see. We would rather be corrected than guess further.

- The VM appears to be a graphical Ubuntu desktop carrying MySQL, MongoDB and Neo4j (installed as systemd services, with Neo4j Desktop used in some handouts), plus Python for the Dash "Dashboard to Rule the Academic World" project. We could not confirm the distro or the database versions.
- **A container can cover the MP and project workflow headless** — SSH or VS Code Remote-SSH for editing, the Dash app on port 8050 and the Neo4j Browser on 7474 reached over an SSH tunnel or a per-student URL. It cannot provide the GUI applications (Neo4j Desktop, MySQL Workbench, MongoDB Compass). **To confirm:** whether any assignment requires those GUIs, or the desktop itself for recording the video demo.
- **systemd is the other question.** Course troubleshooting steps use `sudo systemctl` on the database services. The draft runs them under supervisord with a small `systemctl` shim so those instructions still work; whether that is acceptable is your call.
- **To confirm:** the exact MySQL, MongoDB and Neo4j versions, the size of the Academic World dataset (which we would prefer to pre-bake or share read-only rather than copy per student), and whether teams of two ever need to reach each other's databases.

Draft, never-built files for this class are in this directory: `Dockerfile.suggested` plus its supporting `entrypoint.sh`, `supervisord.conf`, `systemctl-shim.sh`, `requirements.txt`, `my-lowmem.cnf`, `mongod.conf` and `neo4j-lowmem.conf`.

---

## What we are asking for

For your class, the most useful replies are:

1. **Corrections** to anything above.
2. **The software list** — if there is a setup script, package list or image you already use, that is worth more than any amount of guessing on our part.
3. **What would break** if students had a container instead of a VM: anything needing a reboot, a kernel module, a specific address, a GUI, or an exact machine configuration for grading.
4. **Whether the suggested memory limit is plausible** for your assignments' peak usage.

Corrections are welcome as issues or pull requests against this file, or by email.
