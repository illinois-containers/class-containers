# Design

Why this repository is laid out the way it is. Each section names the failure the choice prevents. Most of these failures are ones that surface mid-semester, in front of students, at the worst time.

Nothing here has been built or measured yet. For how the measuring is meant to work, see [BIGTEST.md](BIGTEST.md).

## An offering is a directory

```
<class>/<semester>/           one offering:  cs341/fa26/, cs341/sp27/
<class>/CommentsForClass.md   class-level, for classes not yet onboarded
<class>/Dockerfile.suggested  class-level, untested draft
```

`cs341/fa26/` is Fall 2026 CS 341. `cs341/sp27/` is Spring 2027 CS 341. They are separate directories with separate Dockerfiles and no shared build inputs.

The alternative — one directory per class, with the semester as a CI input or a branch — fails the moment two semesters overlap. Fall 2026 is still running while Spring 2027 is being prepared, and the two may have different instructors. With the semester as a build input, preparing Spring means editing the file Fall is built from. A directory per offering means an instructor can copy last year's and change anything without anyone else noticing.

It also makes "what did students actually have in Fall 2026?" answerable by reading a directory, not by reconstructing a workflow input from a log.

## The path is the only source of truth

`image.yml` **must not** contain `class` or `semester` fields. Validation rejects a manifest that has them.

This looks pedantic until you watch it happen. Starting a new semester is a directory copy. A copied `image.yml` that says `semester: fa26` sitting in `cs341/sp27/` is not a typo anybody notices in review — it reads correctly, it is just in the wrong directory. The build then publishes `cs341:fa26-img1` from the Spring tree, overwriting the Fall tag that students are using. The only field that could have caught it is the one that caused it.

So the class and semester come from the path, always, and a manifest that tries to restate them is a hard failure with a message pointing here. There is no way to express the mistake.

## The manifest is optional

A directory containing only a `Dockerfile` is a valid offering. It builds as `<semester>-<class>-img1`, uses `ci-smoke.sh` if the file is present, amd64 only, status active.

Write an `image.yml` only when you need one of four things:

| Need | Field |
|---|---|
| More than one image in the offering | `images:` with several `subname`s |
| Stop automatic rebuilds of an old semester | `status: frozen` |
| arm64 as well as amd64 | `multiarch: true` |
| Say something to the next person | `notes:` |

Full field list, all optional:

```yaml
status: active            # active | frozen   (default: active)
images:
  - subname: img1         # default: img1
    dockerfile: Dockerfile
    smoke: ci-smoke.sh
multiarch: false          # default: false
notes: >
  Free text.
```

The reason for making it optional is that a required manifest is a required copy, and a required copy is a stale copy. Most offerings have one image built from one Dockerfile, and for those the manifest carries no information the directory does not already have. A file with nothing in it but restated defaults is a file nobody reads and everybody copies.

## Ownership lives in CODEOWNERS

`image.yml` has no `owners` field. Review assignment comes from `/CODEOWNERS` at the repo root and nowhere else.

Same hazard as the semester. An `owners:` list copied into a new offering names last year's instructor, who no longer teaches the course and does not notice the review request. GitHub, meanwhile, has been routing reviews correctly from CODEOWNERS the whole time, so now there are two answers and only one of them is enforced. Keeping ownership in the one file GitHub actually reads means it cannot silently disagree with itself.

## Duplicate, do not inherit

Copying an offering directory is the supported way to start a new semester. `scripts/new-offering.sh` does the copy. There is deliberately **no shared build-time base directory** — no `cs341/common/`, no base Dockerfile that offerings `FROM`.

Sharing looks obviously better right up to the first change. Suppose `cs341/base/Dockerfile` exists and both `fa26` and `sp27` build from it. In January someone adds a package for Spring. Fall 2026 is frozen — but frozen means "we do not rebuild it", and if anything ever does rebuild it, it now rebuilds differently. The archive silently stopped matching what students ran. The duplication buys the one property that matters for a teaching artifact: an old offering's inputs cannot be changed by work on a current one, because nothing current touches them.

The cost is real — a fix applied to both Fall and Spring is two edits — and it is the right trade for a directory that is read a year later to answer "what did the students have?".

`templates/` (if present) is used only at creation time, by `new-offering.sh`. Nothing builds from it.

## Two independent brakes on rebuilding old semesters

The weekly scheduled rebuild runs an offering only if **both** hold:

1. its status is `active` (not `frozen`), and
2. its semester appears in the repo variable `ACTIVE_SEMESTERS`.

Either one alone would be enough, on a good day. The point is that they fail differently. Forgetting to set `status: frozen` on Fall 2026 is an instructor-side omission at the end of a busy semester; forgetting to drop `fa26` from `ACTIVE_SEMESTERS` is a maintainer-side omission. One person forgetting one thing does not rebuild a two-year-old image against packages that have moved on under it.

`workflow_dispatch` can still build a frozen offering, but only with the `force` flag set — a deliberate act, not a default. And a pull request that touches a frozen offering **fails validation** unless the PR carries the `unfreeze` label, so an accidental edit to last year's directory is caught before it merges rather than after it rebuilds.

## Pull requests build but never publish

`push` to `main` builds only the offerings whose files changed. `pull_request` builds and never pushes.

This is not only a safety rule, it is the contribution path. A pull request from an instructor's fork gets a read-only token; it could not push to the registry even if the workflow asked it to. So the workflow does not ask. An instructor without write access to this repository can open a PR, watch their image build and their smoke test run, and iterate — with no credentials, no secrets, and no way to affect a published tag.

## No `latest`

Published tags for one build:

```
ghcr.io/illinois-containers/cs341:fa26-img1
ghcr.io/illinois-containers/cs341:fa26-img1:cs341:fa26-img1-20260919-a1b2c3d
```

The first moves when staff republish. The second never moves. There is no `latest`.

A moving tag mid-semester is the one failure a student cannot diagnose. Their code compiled on Tuesday and does not on Thursday; nothing in their repository changed; the error is in a header they have never opened. Everything they know how to check says nothing changed. Meanwhile a `docker pull` on another machine gets a different image than the one still cached on theirs, so "it works for me" is true for both of them simultaneously.

Dropping `latest` does not remove the moving tag — `cs341:fa26-img1` still moves — but it removes the tag people reach for by habit, and it makes the dated tag the obvious thing to write down. Students pin the digest; see [STUDENTS.md](STUDENTS.md).

The date-plus-short-sha suffix means the tag says when it was built and from which commit, which is what you need when a student reports something a month later.

The registry host is the repo variable `REGISTRY`, default `ghcr.io`, so the whole scheme can move without editing every document.

## The published image is the archive, not the Dockerfile

A Dockerfile is a recipe, not a record. `apt-get install clang` resolved to some version on the day it ran; the repository it read from has since dropped that version, and eventually the release goes end-of-life and the mirror goes away entirely. A three-year-old offering's Dockerfile may simply stop building, correctly, with no bug in it.

That is expected and it is not a problem to solve, because the artifact that matters — the image students actually ran — was published the first time and is still in the registry. The digest is the archive.

Two consequences:

- **Never prune a frozen offering's packages** from the registry. The image is the only copy of what those students had. A retention policy that deletes untagged or old versions must exclude frozen offerings; see [MAINTAINERS.md](MAINTAINERS.md).
- Digest-pinning the base image (`FROM ubuntu:26.04@sha256:...`) extends how long a rebuild stays reproducible, which is why validation warns about an active offering whose base is not digest-pinned. It extends it; it does not make it permanent, because apt repositories drift independently of the base image.

## What validation checks

On every pull request:

| Check | Result |
|---|---|
| `image.yml` parses and matches the schema | FAIL |
| `class` or `semester` present in a manifest | FAIL |
| Two images resolve to the same published name | FAIL |
| A referenced `dockerfile` does not exist | FAIL |
| A referenced `smoke` script does not exist, or is not executable | FAIL |
| The PR touches a frozen offering without the `unfreeze` label | FAIL |
| An active offering's `FROM` is not digest-pinned | WARN |

The digest warning is a warning because there are legitimate reasons to be mid-refresh, and because a hard failure there would push people to pin a digest they have not thought about. The rest are failures because each one is a thing that cannot be correct.

## No secrets

Nothing in this repository needs a secret. GitHub Actions pushes to GHCR using the automatic `GITHUB_TOKEN`, with `permissions: packages: write` granted at the job level. If a design here ever seems to need a registry credential, it is the design that is wrong.

One operational wrinkle that is not a design choice and cannot be fixed from here: GHCR creates a package **private** on its first push, even for a public repository. Someone with org admin rights makes it public, once per package name, before students can pull. [MAINTAINERS.md](MAINTAINERS.md) has the steps.

## Current state

| | |
|---|---|
| `cs341/fa26` | Ubuntu 26.04, matching the student VMs at 26.04.1. Never built. |
| `cs341/sp27` | Debian trixie-slim. Never built. |
| everything else | `CommentsForClass.md` and an untested `Dockerfile.suggested`. |

The course's grader image, `cs341-illinois/docker-base`, is still Ubuntu 24.04 with clang-18. **Both offerings here therefore differ from the grader today.** That is stated in each Dockerfile and it is not resolved: either the grader gets rebased onto these images, or the difference is accepted knowingly. It should not be accepted quietly.
