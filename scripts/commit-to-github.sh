#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_REMOTE="${GIT_REMOTE:-origin}"
COMMIT_MESSAGE=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/commit-to-github.sh [commit message]
  scripts/commit-to-github.sh -m "commit message"
  scripts/commit-to-github.sh --dry-run

Options:
  -m, --message MSG  Commit message. Defaults to "Update project YYYY-MM-DD HH:MM:SS".
  --dry-run          Show the changes that would be committed without staging, committing, or pushing.
  -h, --help         Show this help.

Environment:
  GIT_REMOTE         Remote to push to; defaults to origin.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      COMMIT_MESSAGE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      COMMIT_MESSAGE="$*"
      break
      ;;
  esac
done

cd "$PROJECT_ROOT"
git rev-parse --is-inside-work-tree >/dev/null

BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || { echo "Cannot commit from a detached HEAD state." >&2; exit 1; }
git remote get-url "$GIT_REMOTE" >/dev/null

if [[ -z "$COMMIT_MESSAGE" ]]; then
  COMMIT_MESSAGE="Update project $(date '+%Y-%m-%d %H:%M:%S')"
fi

echo "Project: $PROJECT_ROOT"
echo "Branch:  $BRANCH"
echo "Remote:  $GIT_REMOTE ($(git remote get-url "$GIT_REMOTE"))"
echo
echo "Current Git status:"
git status --short --branch
echo

echo "Checking Git diff for whitespace and conflict-marker problems..."
git diff --check
echo

if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
  echo "No changes to commit."
  exit 0
fi

echo "Changes that will be committed:"
git status --short
git diff --stat || true
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run complete. No files were staged, committed, or pushed."
  exit 0
fi

git add -A
git diff --cached --quiet && { echo "No staged changes to commit."; exit 0; }

echo "Creating commit: $COMMIT_MESSAGE"
git commit -m "$COMMIT_MESSAGE"

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
else
  git push -u "$GIT_REMOTE" "$BRANCH"
fi

echo
echo "Done. Latest commit:"
git --no-pager log -1 --oneline
