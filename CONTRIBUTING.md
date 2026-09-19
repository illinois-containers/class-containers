# Contributing

Corrections are the point of this repository. Most of what is here was assembled from public course materials, so if you teach one of these classes, you know things we had to guess at.

## Who contributes what

| | |
|---|---|
| **Instructors** | Your class's offerings (`<class>/<semester>/`) and your class's `CommentsForClass.md`. Corrections to either are welcome as an issue, a pull request, or an email. |
| **Maintainers** | The workflows, the validation, the shared docs, and repository setup. See [docs/MAINTAINERS.md](docs/MAINTAINERS.md). |

Adding a semester is [docs/ADDING-AN-OFFERING.md](docs/ADDING-AN-OFFERING.md). Why things are shaped the way they are is [docs/DESIGN.md](docs/DESIGN.md).

## This repository and its images are public

Never commit, and never build into an image: keys, tokens, passwords or certificates; MP solutions or unreleased test cases; unreleased handouts or exam material; student work or grades; software that may not be redistributed.

Two things people get wrong: a deleted file is still published, because git keeps history — the fix for a leaked secret is to rotate it. And `COPY` followed by `rm` in a later layer still ships the file, because anyone can unpack the earlier layer.

The README has the full list. Read it before your first PR. If your course genuinely needs a private file at build time, ask first so we can set it up the same way each time.

## Pull requests build, they do not publish

CI builds your offering and runs its smoke test on every pull request, and pushes nothing to the registry. A PR from a fork gets a read-only token, so it could not publish even if it tried. Iterate freely; you need no credentials and no access to this repository.

Publishing happens only on merge to `main`, and only for the offerings whose files changed.

Validation also runs on every PR — schema, no `class:`/`semester:` fields in a manifest, no duplicate image names, referenced files exist and smoke scripts are executable, and no edits to a frozen offering without the `unfreeze` label. The checklist in [docs/ADDING-AN-OFFERING.md](docs/ADDING-AN-OFFERING.md) covers the usual failures.

## Review

`/CODEOWNERS` routes each class directory to its instructor, and that file is the only place ownership is recorded — do not add an `owners:` field to `image.yml`. Your PR gets a review request automatically. Changes to workflows, validation or shared docs go to the default owner.

## Asking for a class to be onboarded

Open an issue named for the class — "Onboard CS 233" — and say who the instructor is and which semester to target. Useful in that issue, roughly in order:

1. An existing setup script, package list, or Docker image you already use. This is worth more than any amount of guessing on our side.
2. What would break without a real VM: a reboot, a kernel module, a GUI, a fixed address, or an exact machine configuration for grading.
3. A plausible memory ceiling for your heaviest assignment.

We will add a `CODEOWNERS` line for you and open a first offering. Nothing is built for your class until you ask.
