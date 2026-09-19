#!/usr/bin/env bash
# Decide which offerings this run should build, and emit the build matrix.
#
# An "offering" is a directory <class>/<semester>/ containing a Dockerfile.
# Class and semester come from the PATH — never from image.yml, which may have
# been copied from another semester. image.yml is optional and only carries
# what the path cannot express: status, extra images, multiarch, notes.
#
# Runs in CI (writes to $GITHUB_OUTPUT) and locally for testing:
#   EVENT=schedule ACTIVE_SEMESTERS=fa26 OWNER=illinois-containers \
#     GITHUB_OUTPUT=/dev/stdout .github/scripts/select-offerings.sh
set -euo pipefail

EVENT="${EVENT:-workflow_dispatch}"
OWNER_LC="$(printf '%s' "${OWNER:?OWNER is required}" | tr '[:upper:]' '[:lower:]')"
REGISTRY="${REGISTRY:-}"; [ -n "$REGISTRY" ] || REGISTRY="ghcr.io"
ACTIVE_SEMESTERS="${ACTIVE_SEMESTERS:-}"
IN_OFFERING="${IN_OFFERING:-}"
IN_SUBNAME="${IN_SUBNAME:-}"
IN_PUSH="${IN_PUSH:-true}"
IN_FORCE="${IN_FORCE:-false}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

note() { echo "$*" >&2; }
fail() { echo "::error::$*" >&2; exit 1; }

have_yq=0
command -v yq >/dev/null 2>&1 && have_yq=1

# ---------------------------------------------------------------- manifest read
# Reads one field from an optional image.yml without requiring yq. The schema is
# deliberately tiny; anything complicated belongs in the Dockerfile.
manifest_status() {  # <offering-dir>
  local f="$1/image.yml"
  [ -f "$f" ] || { echo active; return; }
  local v
  v="$(sed -n 's/^[[:space:]]*status:[[:space:]]*\([a-zA-Z]*\).*/\1/p' "$f" | head -1)"
  echo "${v:-active}"
}
manifest_multiarch() {  # <offering-dir>
  local f="$1/image.yml"
  [ -f "$f" ] || { echo false; return; }
  local v
  v="$(sed -n 's/^[[:space:]]*multiarch:[[:space:]]*\([a-zA-Z]*\).*/\1/p' "$f" | head -1)"
  [ "${v:-false}" = "true" ] && echo true || echo false
}
manifest_arm64_dev() {  # <offering-dir>
  local f="$1/image.yml"
  [ -f "$f" ] || { echo false; return; }
  local v
  v="$(sed -n 's/^[[:space:]]*arm64_dev:[[:space:]]*\([a-zA-Z]*\).*/\1/p' "$f" | head -1)"
  [ "${v:-false}" = "true" ] && echo true || echo false
}
# Emits "subname<TAB>dockerfile<TAB>smoke" per image. With no manifest (the
# common case) that is one line: img1, Dockerfile, ci-smoke.sh if it exists.
manifest_images() {  # <offering-dir>
  local dir="$1" f="$1/image.yml"
  if [ ! -f "$f" ] || ! grep -q '^[[:space:]]*images:' "$f"; then
    local smoke=""; [ -f "$dir/ci-smoke.sh" ] && smoke="ci-smoke.sh"
    printf 'img1\tDockerfile\t%s\n' "$smoke"
    return
  fi
  awk -v dir="$dir" '
    /^[[:space:]]*images:/ { in_images=1; next }
    in_images && /^[^[:space:]]/ { in_images=0 }
    in_images && /^[[:space:]]*-[[:space:]]*subname:/ {
      if (sub != "") print sub "\t" (df != "" ? df : "Dockerfile") "\t" smoke
      sub=$0; gsub(/.*subname:[[:space:]]*/, "", sub); gsub(/[[:space:]"]/, "", sub)
      df=""; smoke=""
      next
    }
    in_images && /^[[:space:]]*dockerfile:/ { df=$0; gsub(/.*dockerfile:[[:space:]]*/, "", df); gsub(/[[:space:]"]/, "", df) }
    in_images && /^[[:space:]]*smoke:/      { smoke=$0; gsub(/.*smoke:[[:space:]]*/, "", smoke); gsub(/[[:space:]"]/, "", smoke) }
    END { if (sub != "") print sub "\t" (df != "" ? df : "Dockerfile") "\t" smoke }
  ' "$f"
}

# -------------------------------------------------------------------- discovery
all_offerings() {
  # <class>/<semester>/Dockerfile, two levels deep only.
  find . -mindepth 3 -maxdepth 3 -name Dockerfile -type f 2>/dev/null \
    | sed 's#^\./##; s#/Dockerfile$##' \
    | grep -Ev '^(\.github|docs|scripts|templates)/' \
    | sort
}

# bash 3.2 (macOS) has no mapfile; this script must run locally too.
OFFERINGS=()
while IFS= read -r __l; do [ -n "$__l" ] && OFFERINGS+=("$__l"); done < <(all_offerings)
[ "${#OFFERINGS[@]}" -gt 0 ] || note "warning: no offerings found"
note "discovered: ${OFFERINGS[*]:-none}"

# ---------------------------------------------------------------- what to build
selected=()
PUSH=true

case "$EVENT" in
  workflow_dispatch)
    PUSH="$IN_PUSH"; [ "$PUSH" = "true" ] || PUSH=false
    if [ -n "$IN_OFFERING" ]; then
      target="${IN_OFFERING%/}"
      printf '%s\n' "${OFFERINGS[@]}" | grep -qx "$target" \
        || fail "no offering at '$target' (expected <class>/<semester>/Dockerfile)"
      selected=("$target")
    else
      for o in "${OFFERINGS[@]}"; do
        [ "$(manifest_status "$o")" = "active" ] && selected+=("$o")
      done
    fi
    # A frozen offering only builds when explicitly forced.
    if [ "$IN_FORCE" != "true" ]; then
      kept=()
      for o in "${selected[@]}"; do
        if [ "$(manifest_status "$o")" = "frozen" ]; then
          fail "'$o' is status: frozen — re-run with force_frozen to build it anyway"
        fi
        kept+=("$o")
      done
      selected=("${kept[@]}")
    fi
    ;;

  push|pull_request)
    # Build only offerings whose own directory changed. Editing a class-level
    # file (CommentsForClass.md, Dockerfile.suggested) builds nothing.
    if [ "$EVENT" = "pull_request" ]; then
      base="${BASE_SHA:-}"
      PUSH=false          # PRs never publish; fork tokens are read-only anyway
    else
      base="${BEFORE_SHA:-}"
    fi
    changed=""
    if [ -n "$base" ] && [ "$base" != "0000000000000000000000000000000000000000" ] \
       && git cat-file -e "${base}^{commit}" 2>/dev/null; then
      changed="$(git diff --name-only "$base" "${AFTER_SHA:-HEAD}" || true)"
    else
      note "no usable base sha; falling back to the last commit"
      changed="$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)"
    fi
    # A change to the workflow or its scripts rebuilds every active offering.
    if printf '%s\n' "$changed" | grep -qE '^\.github/(workflows|scripts)/'; then
      note "CI itself changed; selecting all active offerings"
      for o in "${OFFERINGS[@]}"; do
        [ "$(manifest_status "$o")" = "active" ] && selected+=("$o")
      done
    else
      for o in "${OFFERINGS[@]}"; do
        if printf '%s\n' "$changed" | grep -q "^${o}/"; then
          if [ "$(manifest_status "$o")" = "frozen" ]; then
            note "skipping frozen offering '$o' (validation flags edits to it separately)"
          else
            selected+=("$o")
          fi
        fi
      done
    fi
    ;;

  schedule)
    # Two independent brakes: the offering says active, AND the semester is
    # listed in ACTIVE_SEMESTERS. Either one alone stops an old rebuild.
    [ -n "$ACTIVE_SEMESTERS" ] || { note "ACTIVE_SEMESTERS is unset; nothing is rebuilt on a schedule"; }
    for o in "${OFFERINGS[@]}"; do
      sem="${o##*/}"
      case " ${ACTIVE_SEMESTERS//,/ } " in
        *" $sem "*) [ "$(manifest_status "$o")" = "active" ] && selected+=("$o") ;;
      esac
    done
    ;;

  *)
    fail "unsupported event: $EVENT"
    ;;
esac

# ----------------------------------------------------------------- build matrix
include=""
count=0
for o in "${selected[@]:-}"; do
  [ -n "$o" ] || continue
  class="${o%%/*}"
  semester="${o##*/}"
  multiarch="$(manifest_multiarch "$o")"
  platforms="linux/amd64"
  [ "$multiarch" = "true" ] && platforms="linux/amd64,linux/arm64"

  while IFS=$'\t' read -r subname dockerfile smoke; do
    [ -n "$subname" ] || continue
    [ -n "$IN_SUBNAME" ] && [ "$IN_SUBNAME" != "$subname" ] && continue
    [ -f "$o/$dockerfile" ] || fail "$o: image '$subname' names a missing dockerfile '$dockerfile'"
    smoke_path=""
    [ -n "$smoke" ] && [ -f "$o/$smoke" ] && smoke_path="$o/$smoke"

    # One package per CLASS, semester and subname in the tag:
    #   ghcr.io/<owner>/cs341:sp27-img1
    # Not one package per offering — package visibility is flipped by hand,
    # so per-class means one flip per class ever, instead of one every
    # semester for every image.
    tag_base="${semester}-${subname}"
    entry=$(printf '{"offering":"%s","class":"%s","semester":"%s","subname":"%s","registry":"%s","image":"%s/%s/%s","tag_base":"%s","dockerfile":"%s","context":"%s","smoke":"%s","multiarch":%s,"platforms":"%s","runner":"ubuntu-latest"}' \
      "$o" "$class" "$semester" "$subname" "$REGISTRY" "$REGISTRY" "$OWNER_LC" "$class" "$tag_base" \
      "$o/$dockerfile" "$o" "$smoke_path" "$multiarch" "$platforms")
    include="${include:+$include,}$entry"
    count=$((count + 1))

    # Optional native-arm64 DEV image, for staff on Apple-silicon laptops.
    # Built on a native arm64 runner (not QEMU) so its smoke test is a real
    # test: that is how the arm64 LeakSanitizer gap was found. Published
    # under a distinct -arm64dev tag and never as a student or grading
    # target — see the offering's Known-Issues.md.
    if [ "$(manifest_arm64_dev "$o")" = "true" ]; then
      entry=$(printf '{"offering":"%s","class":"%s","semester":"%s","subname":"%s","registry":"%s","image":"%s/%s/%s","tag_base":"%s","dockerfile":"%s","context":"%s","smoke":"%s","multiarch":false,"platforms":"linux/arm64","runner":"ubuntu-24.04-arm"}' \
        "$o" "$class" "$semester" "${subname}-arm64dev" "$REGISTRY" "$REGISTRY" "$OWNER_LC" "$class" "${tag_base}-arm64dev" \
        "$o/$dockerfile" "$o" "$smoke_path")
      include="${include:+$include,}$entry"
      count=$((count + 1))
    fi
  done < <(manifest_images "$o")
done

matrix="{\"include\":[${include}]}"
note "selected $count image(s): $matrix"
{
  echo "count=$count"
  echo "push=$PUSH"
  echo "matrix=$matrix"
} >> "$GITHUB_OUTPUT"
