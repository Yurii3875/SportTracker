#!/bin/zsh

# Keep this launcher at an ASCII-only path in ~/.local/bin. The .sporttracker
# symlink prevents launchd from receiving a Desktop path with non-ASCII text.
set -eu
cd /Users/yuriiobraztsov/.sporttracker

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "chore: automatic backup $(date '+%Y-%m-%d %H:%M')"
fi

git pull --rebase origin main
git push origin main
