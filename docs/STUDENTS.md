# Using your course container

Your course staff will tell you the image name for your class and semester. It looks like this:

```
ghcr.io/illinois-containers/fa26-cs341-img1
```

Read it as `<semester>-<class>-<subname>`. The image for a different semester is a different image, not a different version of the same one.

Install Docker (Docker Desktop on macOS or Windows, the `docker` package on Linux). No login is needed — these images are public.

## Pull and run

```
docker pull ghcr.io/illinois-containers/fa26-cs341-img1
```

Run it with your work directory mounted, so your files live on your own machine and survive the container:

```
mkdir -p ~/cs341
docker run --rm -it \
  -v ~/cs341:/home/student/work \
  -w /home/student/work \
  ghcr.io/illinois-containers/fa26-cs341-img1 bash
```

You get a shell. Your files are in `/home/student/work` inside the container and in `~/cs341` outside it — the same files, both places. Edit them with your normal editor on your own machine; compile and run them in the container.

`--rm` deletes the container when you exit. That is deliberate: **anything you write outside the mounted directory is gone when you exit.** Keep your work in `work/`.

On Windows PowerShell use `${PWD}` or a full path such as `C:\Users\you\cs341` instead of `~/cs341`.

If your course gives you memory or process limits to reproduce, add them:

```
docker run --rm -it --memory=2g --pids-limit=512 --cpus=4 \
  -v ~/cs341:/home/student/work -w /home/student/work \
  ghcr.io/illinois-containers/fa26-cs341-img1 bash
```

## Pin the digest

There is no `latest` tag, on purpose. The plain tag `fa26-cs341-img1` **moves** when staff publish an update.

That is usually fine. It is not fine the week before a deadline, when you want certainty that the thing compiling your code today is the thing that compiled it yesterday. A pinned digest gives you that: it names one exact image that can never change.

Get the digest of the image you currently have:

```
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/illinois-containers/fa26-cs341-img1
```

which prints something like

```
ghcr.io/illinois-containers/fa26-cs341-img1@sha256:3f8c...
```

Write that whole string down — in your notes, in a `Makefile`, in a shell alias — and use it instead of the tag:

```
docker run --rm -it \
  -v ~/cs341:/home/student/work -w /home/student/work \
  ghcr.io/illinois-containers/fa26-cs341-img1@sha256:3f8c... bash
```

Now `docker pull` of that digest gets you the same bytes on any machine, forever. If you ever have to report a problem to course staff, **include the digest**; it is the difference between a reproducible bug and a shrug.

There are also dated tags, which never move either:

```
ghcr.io/illinois-containers/fa26-cs341-img1:fa26-cs341-img1-20260919-a1b2c3d
```

The digest is stronger, but a dated tag is easier to read and to type.

## When staff publish an update mid-semester

Watch the course announcement for it. Nothing on your machine changes on its own — a pinned digest stays pinned, and even the plain tag only changes when you pull.

To take the update:

```
docker pull ghcr.io/illinois-containers/fa26-cs341-img1
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/illinois-containers/fa26-cs341-img1
```

and record the new digest. Your work is in the mounted directory, so nothing of yours is lost.

If something breaks right after an update, the old digest still works — run it and say so when you report the problem. That comparison is the most useful thing you can hand to staff.

Old images pile up. `docker image ls` shows them, `docker image rm <digest>` removes one, `docker image prune` removes dangling ones.

## A container is not a VM

This is the honest part. A container shares your host's kernel and does not boot. If your course needs any of the following, tell your instructor — it is a real limitation, not something you are doing wrong:

| | |
|---|---|
| Reboot | There is none. Exit and `docker run` again; that is a fresh container, not a reboot. |
| `systemd`, `systemctl`, services | Not running. Start daemons yourself in the foreground, or in a second shell. |
| Kernel modules | Cannot be loaded. `insmod`, `modprobe` and anything needing `/dev/kvm` or raw device access will not work by default. |
| `dmesg`, parts of `/proc` and `/sys` | May show the **host's** kernel, not a kernel of your own. Treat what they say with suspicion. |
| `nproc`, `free`, `top` | Often report the **host's** CPUs and memory, not your container's limits. `make -j$(nproc)` can therefore start far more jobs than your container can afford and get itself killed. Pass an explicit `-j4`. |
| Being killed with no message | Usually the memory limit. `docker run` again with a larger `--memory` to confirm, then tell staff the figure. |

Sanitizers, `gdb`, `valgrind` and `strace` do generally work, but they lean on the host kernel more than most tools do. If one behaves differently than the course notes describe, that is worth reporting rather than working around — and include the digest.

To open a second shell in a container that is already running:

```
docker ps                      # find the container's name
docker exec -it <name> bash
```
