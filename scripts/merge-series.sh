#!/usr/bin/env bash

# Merge a sequence of dependent feature branches one pull request at a time.
# This script deliberately uses merge commits by default to preserve ancestry
# between branches such as feature/49_1 -> feature/49_2 -> feature/49_3.
set -Eeuo pipefail

readonly PROGRAM_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly AUTO_PR_SCRIPT="$SCRIPT_DIR/auto-pr.sh"

BASE_BRANCH=""
MERGE_METHOD="merge"
BRANCH_PREFIX=""
KEEP_BRANCH=false
declare -a BRANCHES=()

usage() {
  cat <<EOF
Usage: $PROGRAM_NAME [options] BRANCH [BRANCH ...]

Create and merge pull requests sequentially, then fast-forward the local base branch.
Provide branches explicitly in their intended order, or select a numbered series with
--prefix. Do not use --auto: a series must finish each merge before the next begins.

Options:
  -b, --base BRANCH       Target branch (default: repository default branch)
  -m, --merge METHOD      Merge method: merge, squash, or rebase (default: merge)
  -p, --prefix PREFIX     Select local branches beginning with PREFIX, natural-sorted
      --keep-branch       Keep merged local and remote feature branches
  -h, --help              Show this help message

Examples:
  # Best for a dependent lesson sequence: preserves branch ancestry.
  $PROGRAM_NAME feature/49_1 feature/49_2 feature/49_3

  # Select feature/49_1, feature/49_2, ... automatically.
  $PROGRAM_NAME --prefix feature/49_

  # Independent branches can use squash merges.
  $PROGRAM_NAME --merge squash feature/48_1 feature/48_2
EOF
}

log() { printf '==> %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    -b|--base) BASE_BRANCH="${2:?Missing value for $1}"; shift 2 ;;
    -m|--merge) MERGE_METHOD="${2:?Missing value for $1}"; shift 2 ;;
    -p|--prefix) BRANCH_PREFIX="${2:?Missing value for $1}"; shift 2 ;;
    --keep-branch) KEEP_BRANCH=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; BRANCHES+=("$@"); break ;;
    -*) die "Unknown option: $1. Run '$PROGRAM_NAME --help' for usage." ;;
    *) BRANCHES+=("$1"); shift ;;
  esac
done

case "$MERGE_METHOD" in merge|squash|rebase) ;; *) die "Merge method must be merge, squash, or rebase." ;; esac
[[ -x "$AUTO_PR_SCRIPT" ]] || die "Required script is missing or not executable: $AUTO_PR_SCRIPT"
[[ -z "$BRANCH_PREFIX" || ${#BRANCHES[@]} -eq 0 ]] || die "Use explicit branches or --prefix, not both."

command -v git >/dev/null || die "git is required."
command -v gh >/dev/null || die "GitHub CLI (gh) is required: https://cli.github.com/"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this command inside a Git repository."
[[ -z "$(git status --porcelain)" ]] || die "Working tree has uncommitted changes. Commit or stash them first."

if [[ -n "$BRANCH_PREFIX" ]]; then
  while IFS= read -r branch; do
    [[ -n "$branch" ]] && BRANCHES+=("$branch")
  done < <(git for-each-ref --format='%(refname:short)' "refs/heads/$BRANCH_PREFIX*" | LC_ALL=C sort -V)
fi
(( ${#BRANCHES[@]} > 0 )) || die "No branches were selected."

if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
fi

for branch in "${BRANCHES[@]}"; do
  git show-ref --verify --quiet "refs/heads/$branch" || die "Local branch does not exist: $branch"
  [[ "$branch" != "$BASE_BRANCH" ]] || die "The base branch cannot be in the series: $branch"
done

log "Processing ${#BRANCHES[@]} branch(es) into $BASE_BRANCH using $MERGE_METHOD merges"
for index in "${!BRANCHES[@]}"; do
  branch="${BRANCHES[$index]}"
  log "[$((index + 1))/${#BRANCHES[@]}] Checking out $branch"
  git switch "$branch"

  auto_pr_args=(--base "$BASE_BRANCH" --merge "$MERGE_METHOD")
  $KEEP_BRANCH && auto_pr_args+=(--keep-branch)
  "$AUTO_PR_SCRIPT" "${auto_pr_args[@]}"
done

log "Final update of local $BASE_BRANCH"
git switch "$BASE_BRANCH"
git pull --ff-only origin "$BASE_BRANCH"
log "Series complete. Local $BASE_BRANCH is up to date."
