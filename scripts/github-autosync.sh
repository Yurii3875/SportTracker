#!/bin/zsh

# Creates a local backup commit and sends it to GitHub. Launchd runs this script
# every minute; failed network attempts are retried on the next run.
set -eu

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "chore: automatic backup $(date '+%Y-%m-%d %H:%M')"
fi

git pull --rebase origin main
git push origin main
