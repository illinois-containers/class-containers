# class-containers

Container images that aim to give CS students the environment their course needs, in place of a per-student virtual machine.

A VM gives each student a whole machine: its own kernel, several gigabytes of RAM reserved whether or not they are used, and a long boot. For most courses the student only needs a toolchain, a shell and a place to run their code. A container provides that using the memory it actually touches, which means more students per host and a faster start — at the cost of sharing the host's kernel, which some courses cannot do. Working out which courses those are is most of the work here.

## Status

**Early. One offering is real; everything else is a proposal.**

| | |
|---|---|
| `cs341/sp27/` | The pilot. Builds, publishes, and passes its smoke test on amd64. Debian trixie-slim, derived from the course's grader image. |
| every other `<class>/` | A `CommentsForClass.md` for that instructor, and an untested `Dockerfile.suggested`. Never built, never run. |

Published today: `cs341:sp27-img1` (amd64, for students and the farm) and `cs341:sp27-img1-arm64dev` (arm64, staff laptops only — leak detection does not work there; see `cs341/sp27/Known-Issues.md`).

## This repository and its images are public

Anyone can read this repository and pull the images it builds. Treat every file here, and everything baked into a layer, as published.

**Never commit or build into an image:**

- API keys, tokens, passwords, certificates or SSH private keys — including ones only meant for a grader or an internal service
- MP solutions, reference implementations, or test cases students have not seen
- Unreleased handouts, exam material, or anything under embargo until a future semester
- Student work, grades, or anything else covered by FERPA
- Licensed third-party software that may not be redistributed

Two things people get wrong:

- **A deleted file is still published.** Git keeps history, and a pushed commit cannot be unpublished — the fix for a leaked secret is to rotate it, not to delete the file.
- **`COPY` then `rm` in a later layer still ships the file.** Anyone can unpack the earlier layer. If a build genuinely needs a private file, it must come from a build secret or a private source at build time, never from this repository.

Course material that cannot be public — a licensed tool, a private fork, unpublished solutions — should live in a private repository or an internal artifact store and be fetched at build time. Ask before adding one, so we can set it up the same way each time.

## Layout

```
<class>/CommentsForClass.md      what we think this class needs, and what we could not confirm
<class>/Dockerfile.suggested     untested draft, a starting point for discussion
<class>/<semester>/              a real offering: Dockerfile, image.yml, ci-smoke.sh
```

The semester lives in the directory name, not in a build setting. Duplicating a semester is a directory copy, so an instructor can fork last year's offering and change it without touching anyone else's, and Fall and Spring can have different instructors and different images.

## Image names

```
ghcr.io/illinois-containers/<class>:<semester>-<subname>
e.g. ghcr.io/illinois-containers/cs341:sp27-img1
```

The sub-name lets one class publish more than one image — a student image and a grader image, say. There is deliberately no `latest` tag: a moving tag mid-semester is the one failure students cannot diagnose. Pin the digest.

## If you teach one of these classes

Read `CommentsForClass.md` in your class's directory. It records what we believe your course needs and — more usefully — what we could not work out from public materials. Corrections are welcome as an issue, a pull request, or an email. We would much rather be corrected than keep guessing.

Everything in this repository was assembled from public course materials. **No memory figure here has been measured**; replacing those estimates with real numbers is what the CS 341 pilot is for.

## Contributing an offering

Copy an existing offering directory, edit `image.yml`, open a pull request. CI builds it without publishing, so a pull request is safe. Old semesters are marked `frozen` and are never rebuilt automatically.
