# Auto PR Merger

`auto-pr.sh` is a small, safe wrapper around Git and the [GitHub CLI](https://cli.github.com/). It pushes your current feature branch, creates or reuses its pull request, merges it, and updates your local base branch.

It is useful for a sequence of focused lesson branches such as `feature/49_1`, `feature/49_2`, and so on: commit the lesson, run one command, then start the next branch from an up-to-date `main`.

## Requirements

- Git 2.23+ (`git switch` is used)
- GitHub CLI installed and authenticated (`gh auth login`)
- An `origin` remote that points to a GitHub repository
- Permission to create and merge pull requests in that repository

## Usage

From a committed feature branch:

```bash
chmod +x scripts/auto-pr.sh
./scripts/auto-pr.sh
```

The default target is the repository's default branch, the PR title is the latest commit subject, and the default merge strategy is **squash**. After a successful merge, the remote branch is deleted, the local default branch is fast-forwarded, and the local feature branch is deleted.

```bash
# Use a different base branch and merge strategy
./scripts/auto-pr.sh --base develop --merge rebase

# Supply PR metadata
./scripts/auto-pr.sh --title "Create a TabNavigator" --body "Closes #49"

# Let GitHub merge automatically once required checks/reviews pass
./scripts/auto-pr.sh --auto
```

Run `./scripts/auto-pr.sh --help` for all options.

## Merge a branch series

For a dependent sequence such as `feature/49_1`, `feature/49_2`, and `feature/49_3`, use the series runner. It checks out one branch at a time, pushes it, creates and merges its PR, then moves to the next branch. It finishes with `git pull --ff-only origin <base-branch>`.

```bash
# Explicit order is safest
./scripts/merge-series.sh feature/49_1 feature/49_2 feature/49_3

# Or select every local branch with a common numbered prefix
./scripts/merge-series.sh --prefix feature/49_
```

The series runner defaults to `--merge merge`, rather than squash, because dependent branches share history. Keeping merge commits means the next PR contains only its new lesson. Use `--merge squash` only when the selected branches are independent. The runner stops at the first failure, leaving the repository on the affected branch so it can be fixed and rerun.

## Safety behavior

- Refuses to run on the base branch or a detached `HEAD`.
- Refuses a dirty working tree by default, preventing accidental cleanup of uncommitted work.
- Reuses an existing open PR for the branch instead of creating a duplicate.
- Verifies the PR state before local cleanup. With `--auto`, cleanup is intentionally deferred until GitHub has actually merged the PR.
- Use `--keep-branch` to retain feature branches or `--allow-dirty` to push/create/merge without local cleanup.

## Notes

Repository branch-protection rules and GitHub merge settings still apply. If a PR requires checks or approvals, use `--auto` to enable GitHub auto-merge (when allowed), or merge it after those requirements pass and then update your branch manually.
