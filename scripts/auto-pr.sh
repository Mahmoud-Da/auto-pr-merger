#!/usr/bin/env bash

# Push the current branch, create (or reuse) its GitHub pull request, merge it,
# then update the local base branch. Requires: git, GitHub CLI (gh).
set -Eeuo pipefail

readonly PROGRAM_NAME="${0##*/}"

BASE_BRANCH=""
MERGE_METHOD="squash"
PR_TITLE=""
PR_BODY=""
AUTO_MERGE=false
DELETE_BRANCH=false
ALLOW_DIRTY=false

usage() {
  cat <<EOF
Usage: $PROGRAM_NAME [options]

Push the current feature branch, create or reuse its pull request, and merge it.

Options:
  -b, --base BRANCH       Target branch (default: repository default branch)
  -m, --merge METHOD      Merge method: merge, squash, or rebase (default: squash)
  -t, --title TITLE       Pull request title (default: latest commit subject)
      --body TEXT         Pull request body
      --auto              Enable GitHub auto-merge if required checks are pending
      --delete-branch     Delete the merged local and remote branch
      --allow-dirty       Allow uncommitted changes; local cleanup is skipped
  -h, --help              Show this help message

Examples:
  $PROGRAM_NAME
  $PROGRAM_NAME --base develop --merge rebase
  $PROGRAM_NAME --title "Add tab navigation" --body "Closes #49"
EOF
}

log() { printf '==> %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    -b|--base) BASE_BRANCH="${2:?Missing value for $1}"; shift 2 ;;
    -m|--merge) MERGE_METHOD="${2:?Missing value for $1}"; shift 2 ;;
    -t|--title) PR_TITLE="${2:?Missing value for $1}"; shift 2 ;;
    --body) PR_BODY="${2:?Missing value for $1}"; shift 2 ;;
    --auto) AUTO_MERGE=true; shift ;;
    --delete-branch) DELETE_BRANCH=true; shift ;;
    --allow-dirty) ALLOW_DIRTY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1. Run '$PROGRAM_NAME --help' for usage." ;;
  esac
done

case "$MERGE_METHOD" in merge|squash|rebase) ;; *) die "Merge method must be merge, squash, or rebase." ;; esac

command -v git >/dev/null || die "git is required."
command -v gh >/dev/null || die "GitHub CLI (gh) is required: https://cli.github.com/"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this command inside a Git repository."
git remote get-url origin >/dev/null 2>&1 || die "The repository needs an 'origin' remote."
gh auth status >/dev/null 2>&1 || die "Authenticate GitHub CLI first with: gh auth login"

CURRENT_BRANCH="$(git branch --show-current)"
[[ -n "$CURRENT_BRANCH" ]] || die "Detached HEAD is not supported. Check out a feature branch first."

if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
fi
[[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]] || die "You are on '$BASE_BRANCH'. Check out a feature branch first."

if ! $ALLOW_DIRTY && [[ -n "$(git status --porcelain)" ]]; then
  die "Working tree has uncommitted changes. Commit/stash them or use --allow-dirty."
fi

if [[ -z "$PR_TITLE" ]]; then
  COMMIT_SUBJECT="$(git log -1 --pretty=%s)"
  if [[ "$COMMIT_SUBJECT" =~ ^(.+)[[:space:]](-[[:space:]]*#[0-9]+)$ ]]; then
    PR_TITLE="${BASH_REMATCH[1]}"
    PR_BODY="${PR_BODY:-${BASH_REMATCH[2]}}"
  else
    PR_TITLE="$COMMIT_SUBJECT"
  fi
fi
[[ -n "$PR_TITLE" ]] || die "Unable to determine a pull request title."

log "Pushing $CURRENT_BRANCH to origin"
git push --set-upstream origin "$CURRENT_BRANCH"

PR_URL="$(gh pr list --head "$CURRENT_BRANCH" --state open --json url --jq '.[0].url')"
if [[ -z "$PR_URL" || "$PR_URL" == "null" ]]; then
  log "Creating pull request into $BASE_BRANCH"
  create_args=(pr create --base "$BASE_BRANCH" --head "$CURRENT_BRANCH" --title "$PR_TITLE")
  if [[ -n "$PR_BODY" ]]; then
    create_args+=(--body "$PR_BODY")
  else
    create_args+=(--fill)
  fi
  PR_URL="$(gh "${create_args[@]}")"
else
  log "Reusing open pull request: $PR_URL"
fi

log "Merging pull request with $MERGE_METHOD strategy"
merge_args=(pr merge "$PR_URL" "--$MERGE_METHOD")
$DELETE_BRANCH && merge_args+=(--delete-branch)
$AUTO_MERGE && merge_args+=(--auto)
gh "${merge_args[@]}"

PR_STATE="$(gh pr view "$PR_URL" --json state --jq .state)"
if [[ "$PR_STATE" != "MERGED" ]]; then
  log "Pull request is not merged yet (state: $PR_STATE). GitHub will merge it when requirements pass."
  exit 0
fi

if $ALLOW_DIRTY; then
  log "Pull request merged. Skipping local cleanup because --allow-dirty was used."
  exit 0
fi

log "Updating local $BASE_BRANCH"
git switch "$BASE_BRANCH"
git pull --ff-only origin "$BASE_BRANCH"

if $DELETE_BRANCH; then
  log "Deleting local branch $CURRENT_BRANCH"
  git branch -d "$CURRENT_BRANCH" 2>/dev/null || \
    log "Local branch was already removed or needs manual cleanup."
fi

log "Done: $PR_URL"
