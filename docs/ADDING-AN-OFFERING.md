# Adding an offering

An offering is one class in one semester: a directory like `cs341/sp27/`. This is how you start next semester's from last year's.

You need a GitHub account and Docker. You do not need write access to this repository — fork it, open a pull request, and CI will build your image without publishing it. You do not need any credentials or secrets, ever.

## 1. Copy last year's directory

```
scripts/new-offering.sh cs341 fa27
```

That copies the most recent existing `cs341/*` offering to `cs341/fa27/`, strips any `class:`/`semester:` fields out of a copied `image.yml`, sets `status: active`, and prints what to do next. It refuses to overwrite an existing directory.

To copy from a specific offering rather than the newest:

```
scripts/new-offering.sh cs341 fa27 --from cs341/sp27
```

Or do it by hand — the script does nothing magic:

```
cp -r cs341/sp27 cs341/fa27
```

Copying is the supported way to start a semester. There is no shared base directory to inherit from, on purpose: see [DESIGN.md](DESIGN.md#duplicate-do-not-inherit).

## 2. Edit the Dockerfile

At minimum:

- **Refresh the base image digest.** The copied `FROM` pins a digest resolved a year ago. Get the current one:

  ```
  docker pull ubuntu:26.04
  docker inspect --format='{{index .RepoDigests 0}}' ubuntu:26.04
  ```

  and paste it into the `FROM` line. Note the date in the comment above it, as the existing files do.

- **Read the "Before this is used for grading" block** at the bottom of the file you copied and act on anything still outstanding. In `cs341/sp27/Dockerfile` that currently includes regenerating the apt pins and confirming version agreement with the autograder.

- **Add or drop packages** the new semester's MPs need. Say why in a comment; the comment is the part a future maintainer reads.

## 3. Add an `image.yml` only if you need one

A directory with just a `Dockerfile` is complete. It builds as `<semester>-<class>-img1`, uses `ci-smoke.sh` if present, amd64 only, active.

Add a manifest only for: more than one image, freezing, arm64, or a note worth leaving.

```yaml
status: active
images:
  - subname: img1
    dockerfile: Dockerfile
    smoke: ci-smoke.sh
multiarch: false
notes: >
  Why this image is the way it is.
```

**Do not add**, in `image.yml` or anywhere else:

| Don't | Why |
|---|---|
| `class:` or `semester:` | The path is the truth. Validation **fails** if these appear — a copied manifest with last year's semester would publish over a tag students are using. |
| `owners:` | Ownership is in `/CODEOWNERS` only. A copied owners list names last year's instructor. |
| Any secret, token, key or password | This repository and its images are public. See the README. |
| Solutions, unreleased handouts, exam material | Same. A deleted file is still published. |

## 4. Test locally

Build:

```
docker build -t cs341-fa27-test cs341/fa27
```

Run the smoke test the way CI will — inside the freshly built container:

```
docker run --rm -v "$PWD/cs341/fa27/ci-smoke.sh:/ci-smoke.sh:ro" \
  cs341-fa27-test bash /ci-smoke.sh
```

If you copied a smoke test, it probably still asserts last year's tool versions. Update the expected versions to whatever your image now resolves to, or it will fail on the first build — which is the point of it.

Poke around interactively:

```
docker run --rm -it cs341-fa27-test bash
```

Optionally, run the heavy test with the limits you intend to impose on students. This is minutes to an hour, not seconds, and it is how the memory numbers in this project stop being guesses:

```
docker run --rm --memory=2g --pids-limit=512 --cpus=4 \
  -v "$PWD/cs341/fa27/bigtest.sh:/bigtest.sh:ro" \
  cs341-fa27-test bash /bigtest.sh --level full
```

See [BIGTEST.md](BIGTEST.md) for what a good one exercises and how to read the output. If it reports OOM kills, the limit is too low — raise it and record the real figure in your class's `CommentsForClass.md`.

Make sure any script you added is executable, because validation checks that:

```
chmod +x cs341/fa27/ci-smoke.sh cs341/fa27/bigtest.sh
```

## 5. Open the pull request

One offering per PR where you can. Say in the description what changed from the semester you copied, and anything you could not verify.

**CI on the pull request builds your image and runs your smoke test. It does not publish anything.** A PR from a fork gets a read-only token, so there is no way for it to touch a published tag. Iterate as much as you like.

Validation will check:

| Check | |
|---|---|
| `image.yml` parses and matches the schema | fail |
| no `class:` or `semester:` fields | fail |
| no two images resolve to the same published name | fail |
| the `dockerfile` and `smoke` files exist, and `smoke` is executable | fail |
| the PR does not touch a frozen offering — unless it has the `unfreeze` label | fail |
| an active offering's `FROM` is digest-pinned | warn |

Plus the build itself, and the smoke test inside it.

### PR checklist

- [ ] Directory is `<class>/<semester>/`, semester like `fa27` / `sp27` / `su27`
- [ ] `FROM` is digest-pinned, and the digest is one I resolved today
- [ ] No `class:`, `semester:` or `owners:` in `image.yml` (or no `image.yml` at all)
- [ ] No secrets, solutions, or unreleased material
- [ ] `docker build` succeeds locally
- [ ] `ci-smoke.sh` passes in the built image, and asserts *this* image's versions, not last year's
- [ ] Scripts are executable (`chmod +x`)
- [ ] I did not edit another semester's directory
- [ ] The PR description says what I changed and what I could not verify

## 6. After merge

On push to `main`, only the offerings whose files changed are built, and those are pushed to the registry as:

```
ghcr.io/illinois-containers/cs341:fa27-img1
ghcr.io/illinois-containers/cs341:fa27-img1:cs341:fa27-img1-20270819-a1b2c3d
```

The first tag moves when staff republish. The second never moves. There is no `latest` — see [DESIGN.md](DESIGN.md#no-latest). Point students at [STUDENTS.md](STUDENTS.md), which tells them to pin the digest.

Two things a maintainer has to do once, which you should ask for rather than assume:

- **A brand-new image name is created as a private package on its first push**, even though this repository is public. An org admin makes it public before students can pull. Once per package name. See [MAINTAINERS.md](MAINTAINERS.md).
- **`ACTIVE_SEMESTERS` must list your semester** for the weekly rebuild to include your offering, and last year's offering should be set to `status: frozen`.

Thereafter the weekly schedule rebuilds your offering as long as it is active *and* its semester is in `ACTIVE_SEMESTERS`. A one-off rebuild is `workflow_dispatch` with your offering path.

When the semester ends, add `status: frozen` to your `image.yml`. That is the signal that the published image is now an archive, not a thing under maintenance.
