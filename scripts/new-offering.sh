#!/usr/bin/env bash
# new-offering.sh — start a new semester's offering by copying an existing one.
#
#   scripts/new-offering.sh <class> <semester> [--from <class>/<semester>]
#
#   scripts/new-offering.sh cs341 fa27
#   scripts/new-offering.sh cs341 fa27 --from cs341/sp27
#
# Copies an existing offering directory to <class>/<semester>/, strips any
# class:/semester: fields out of a copied image.yml (the path is the only
# source of truth — validation rejects those fields), sets status: active,
# and prints what to do next.
#
# Without --from, the source is the most recent existing offering of that
# class, or templates/offering if the class has none.
#
# Copying rather than inheriting is deliberate: see docs/DESIGN.md. Nothing
# here is magic — `cp -r cs341/sp27 cs341/fa27` does the same job.

set -euo pipefail

prog="$(basename "$0")"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

die() { printf '%s: %s\n' "$prog" "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

usage() {
  cat >&2 <<EOF
usage: $prog <class> <semester> [--from <class>/<semester>]

  <class>     class directory name, e.g. cs341
  <semester>  fa|sp|su|wi followed by two digits, e.g. fa27, sp27, su27
  --from      offering to copy (default: the most recent offering of <class>,
              or templates/offering if the class has none)
EOF
  exit 2
}

# ---- arguments -------------------------------------------------------------

class=""
semester=""
from=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from)
      [ $# -ge 2 ] || die "--from needs a value, e.g. --from cs341/sp27"
      from="$2"
      shift 2
      ;;
    --from=*)
      from="${1#--from=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [ -z "$class" ]; then
        class="$1"
      elif [ -z "$semester" ]; then
        semester="$1"
      else
        die "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[ -n "$class" ] && [ -n "$semester" ] || usage

case "$class" in
  *[!a-z0-9]*|"") die "class '$class' should be lowercase letters and digits, e.g. cs341" ;;
esac

# fa26, sp27, su27, wi27 — the semester is the directory name and the tag.
case "$semester" in
  fa[0-9][0-9]|sp[0-9][0-9]|su[0-9][0-9]|wi[0-9][0-9]) : ;;
  *) die "semester '$semester' should look like fa26, sp27, su27 or wi27" ;;
esac

dest="$repo_root/$class/$semester"
dest_rel="$class/$semester"

[ -e "$dest" ] && die "$dest_rel already exists — refusing to overwrite it"

# ---- choose the source -----------------------------------------------------

if [ -n "$from" ]; then
  src="$repo_root/$from"
  src_rel="$from"
  [ -d "$src" ] || die "--from $from: no such directory"
  [ -f "$src/Dockerfile" ] || die "--from $from: no Dockerfile there — is it an offering?"
else
  src=""
  src_rel=""
  # Most recent existing offering of this class: any subdirectory holding a
  # Dockerfile, taking the last in sort order as a rough "most recent".
  if [ -d "$repo_root/$class" ]; then
    for candidate in "$repo_root/$class"/*/; do
      [ -f "${candidate}Dockerfile" ] || continue
      src="${candidate%/}"
    done
  fi
  if [ -n "$src" ]; then
    src_rel="${src#"$repo_root"/}"
  elif [ -f "$repo_root/templates/offering/Dockerfile" ]; then
    src="$repo_root/templates/offering"
    src_rel="templates/offering"
  else
    die "no existing offering for $class and no templates/offering — pass --from <class>/<semester>"
  fi
fi

[ "$src" = "$dest" ] && die "source and destination are the same directory"

# ---- copy ------------------------------------------------------------------

mkdir -p "$repo_root/$class"
cp -R "$src" "$dest"
note "copied $src_rel -> $dest_rel"

manifest="$dest/image.yml"

if [ -f "$manifest" ]; then
  tmp="$manifest.new.$$"
  # Drop class:/semester:/owners: — the path is the truth and ownership lives
  # in CODEOWNERS; validation fails a manifest that names class or semester.
  # Only top-level keys (no leading whitespace) are touched.
  awk '
    /^[[:space:]]*#/ { print; next }
    /^(class|semester|owners)[[:space:]]*:/ { next }
    { print }
  ' "$manifest" > "$tmp"
  mv "$tmp" "$manifest"

  # Force status: active — a copied frozen offering must not start frozen.
  if grep -q '^status[[:space:]]*:' "$manifest"; then
    tmp="$manifest.new.$$"
    sed 's/^status[[:space:]]*:.*/status: active/' "$manifest" > "$tmp"
    mv "$tmp" "$manifest"
  else
    printf 'status: active\n' >> "$manifest"
  fi
  note "image.yml: removed any class/semester/owners fields, set status: active"
else
  note "no image.yml (fine — a Dockerfile alone builds as ${semester}-${class}-img1)"
fi

# ---- next steps ------------------------------------------------------------

image="${semester}-${class}-img1"

cat <<EOF

Created $dest_rel from $src_rel.

Next:

  1. Edit $dest_rel/Dockerfile.
     Read its "Before this is used for grading" block and act on what is
     still outstanding.

  2. Refresh the base image digest — the copied FROM pins one resolved for a
     previous semester:

       docker pull <base>:<tag>
       docker inspect --format='{{index .RepoDigests 0}}' <base>:<tag>

     Paste it into the FROM line and note today's date in the comment above it.

  3. Build and smoke-test locally:

       docker build -t ${class}-${semester}-test $dest_rel
       docker run --rm -v "\$PWD/$dest_rel/ci-smoke.sh:/ci-smoke.sh:ro" \\
         ${class}-${semester}-test bash /ci-smoke.sh

     A copied smoke test still asserts last year's tool versions. Update it.

  4. Open a pull request. CI builds it and runs the smoke test; it publishes
     nothing. On merge it is pushed as:

       ghcr.io/illinois-containers/$image

Do NOT add class:, semester: or owners: to image.yml — validation rejects the
first two, and ownership belongs in /CODEOWNERS.

Details: docs/ADDING-AN-OFFERING.md
EOF
