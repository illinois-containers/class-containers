#!/usr/bin/env bash
# Validate every offering in the repo. This is the gatekeeper for instructor
# pull requests, so its errors have to say what to do, not just what is wrong.
#
# Local use:
#   .github/scripts/validate-offerings.sh
# In CI, additionally set CHANGED_FILES (newline separated) and PR_LABELS
# (comma separated) so the frozen-offering check can run.
set -uo pipefail

CHANGED_FILES="${CHANGED_FILES:-}"
PR_LABELS="${PR_LABELS:-}"

errors=0
warnings=0
err()  { echo "::error::$*"; errors=$((errors + 1)); }
warn() { echo "::warning::$*"; warnings=$((warnings + 1)); }
ok()   { echo "  ok    $*"; }

echo "== discovering offerings"
# bash 3.2 (macOS) has no mapfile, and this must run locally as well as in CI.
OFFERINGS=()
while IFS= read -r line; do [ -n "$line" ] && OFFERINGS+=("$line"); done < <(
  find . -mindepth 3 -maxdepth 3 -name Dockerfile -type f 2>/dev/null \
  | sed 's#^\./##; s#/Dockerfile$##' \
  | grep -Ev '^(\.github|docs|scripts|templates)/' | sort)

if [ "${#OFFERINGS[@]}" -eq 0 ]; then
  echo "no offerings found (expected <class>/<semester>/Dockerfile)"
  exit 0
fi
printf '  found: %s\n' "${OFFERINGS[*]}"

# "image<TAB>offering" per line; bash 3.2 has no associative arrays.
seen_images=""

for o in "${OFFERINGS[@]}"; do
  class="${o%%/*}"
  semester="${o##*/}"
  echo "== $o"

  # --- the path is the source of truth -------------------------------------
  case "$semester" in
    fa[0-9][0-9]|sp[0-9][0-9]|su[0-9][0-9]|wi[0-9][0-9]) ok "semester '$semester' looks right" ;;
    *) err "$o: '$semester' is not a semester directory. Use fa26, sp27, su27 or wi27." ;;
  esac
  case "$class" in
    [a-z]*[0-9]*) ok "class '$class' looks right" ;;
    *) err "$o: '$class' does not look like a class directory (expected e.g. cs341)." ;;
  esac

  manifest="$o/image.yml"
  status=active
  multiarch=false

  if [ -f "$manifest" ]; then
    # --- fields the path already defines must not be repeated --------------
    for forbidden in class semester owners; do
      if grep -qE "^[[:space:]]*${forbidden}:" "$manifest"; then
        err "$o/image.yml: remove the '${forbidden}:' field. The directory path defines class and semester, and CODEOWNERS defines ownership. A copied manifest with a stale value is exactly what this rule prevents."
      fi
    done

    status="$(sed -n 's/^[[:space:]]*status:[[:space:]]*\([a-zA-Z]*\).*/\1/p' "$manifest" | head -1)"
    status="${status:-active}"
    case "$status" in
      active|frozen) ok "status: $status" ;;
      *) err "$o/image.yml: status must be 'active' or 'frozen', got '$status'." ;;
    esac

    multiarch="$(sed -n 's/^[[:space:]]*multiarch:[[:space:]]*\([a-zA-Z]*\).*/\1/p' "$manifest" | head -1)"
    multiarch="${multiarch:-false}"
    case "$multiarch" in true|false) ;; *) err "$o/image.yml: multiarch must be true or false." ;; esac
  else
    ok "no image.yml — using defaults (img1, Dockerfile, ci-smoke.sh, active)"
  fi

  # --- images, defaulted from the path when there is no manifest -----------
  if [ -f "$manifest" ] && grep -q '^[[:space:]]*images:' "$manifest"; then
    rows=()
    while IFS= read -r __r; do [ -n "$__r" ] && rows+=("$__r"); done < <(awk '
      /^[[:space:]]*images:/ { in_images=1; next }
      in_images && /^[^[:space:]]/ { in_images=0 }
      in_images && /^[[:space:]]*-[[:space:]]*subname:/ {
        if (sub != "") print sub "\t" (df != "" ? df : "Dockerfile") "\t" smoke
        sub=$0; gsub(/.*subname:[[:space:]]*/, "", sub); gsub(/[[:space:]"]/, "", sub); df=""; smoke=""; next
      }
      in_images && /^[[:space:]]*dockerfile:/ { df=$0; gsub(/.*dockerfile:[[:space:]]*/, "", df); gsub(/[[:space:]"]/, "", df) }
      in_images && /^[[:space:]]*smoke:/      { smoke=$0; gsub(/.*smoke:[[:space:]]*/, "", smoke); gsub(/[[:space:]"]/, "", smoke) }
      END { if (sub != "") print sub "\t" (df != "" ? df : "Dockerfile") "\t" smoke }
    ' "$manifest")
  else
    smoke_default=""; [ -f "$o/ci-smoke.sh" ] && smoke_default="ci-smoke.sh"
    rows=("img1	Dockerfile	$smoke_default")
  fi

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r subname dockerfile smoke <<< "$row"
    [ -n "$subname" ] || { err "$o: an entry under images: has no subname."; continue; }

    case "$subname" in
      [a-z0-9]*) ;;
      *) err "$o: subname '$subname' must start with a lowercase letter or digit." ;;
    esac

    image="${class}:${semester}-${subname}"
    prior="$(printf '%s\n' "$seen_images" | awk -F'\t' -v i="$image" '$1==i{print $2; exit}')"
    if [ -n "$prior" ]; then
      err "$o: image name '$image' is already produced by $prior. Two offerings cannot publish the same name."
    else
      seen_images="$seen_images$image	$o
"
    fi
    ok "image: $image"

    [ -f "$o/$dockerfile" ] || err "$o: image '$subname' names '$dockerfile', which does not exist."

    if [ -n "$smoke" ]; then
      if [ ! -f "$o/$smoke" ]; then
        err "$o: image '$subname' names smoke script '$smoke', which does not exist."
      elif [ ! -x "$o/$smoke" ]; then
        err "$o/$smoke is not executable. Run: chmod +x $o/$smoke"
      else
        bash -n "$o/$smoke" 2>/dev/null || err "$o/$smoke has a syntax error."
        ok "smoke: $smoke"
      fi
    fi

    # --- base image pinning (warning, not an error) ------------------------
    if [ -f "$o/$dockerfile" ] && [ "$status" = "active" ]; then
      if grep -qE '^[[:space:]]*FROM[[:space:]]+[^[:space:]]+@sha256:' "$o/$dockerfile"; then
        ok "base image is digest-pinned"
      else
        warn "$o/$dockerfile: base image is not digest-pinned. A rebuild may silently get a different base. Use FROM image:tag@sha256:..."
      fi
    fi
  done

  # --- frozen offerings must not be edited without the unfreeze label ------
  if [ "$status" = "frozen" ] && [ -n "$CHANGED_FILES" ]; then
    if printf '%s\n' "$CHANGED_FILES" | grep -q "^${o}/"; then
      if printf '%s' "$PR_LABELS" | tr ',' '\n' | grep -qx "unfreeze"; then
        warn "$o is frozen but the 'unfreeze' label is present — allowing the edit."
      else
        err "$o is marked status: frozen and this change touches it. Frozen offerings are finished semesters and their published images are the archive. If you really must change it, add the 'unfreeze' label to the PR."
      fi
    fi
  fi
done

echo "=============================================================="
echo "offerings: ${#OFFERINGS[@]}   errors: $errors   warnings: $warnings"
[ "$errors" -eq 0 ] || echo "fix the errors above; see docs/ADDING-AN-OFFERING.md"
exit $(( errors > 0 ? 1 : 0 ))
