#!/bin/zsh

# launchd does not reliably pass non-ASCII paths to command arguments.
# Keep this launcher at an ASCII-only path in ~/.local/bin.
exec /bin/zsh "/Users/yuriiobraztsov/Desktop/Мой проект по sport tracker ( Идеи )/SportTracker/scripts/github-autosync.sh"
