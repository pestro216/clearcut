#!/bin/bash
# Publishes a folder to the qa-results branch: QA/publish.sh SRC DEST "message"
set -e
SRC="$1"; DEST="$2"; MSG="$3"
git config user.name "Clearcut build"
git config user.email "actions@users.noreply.github.com"
git worktree remove --force /tmp/qa 2>/dev/null || true
rm -rf /tmp/qa
git worktree prune
if git ls-remote --exit-code origin qa-results >/dev/null 2>&1; then
  git fetch -q origin qa-results
  git worktree add -q /tmp/qa origin/qa-results --detach
else
  git worktree add -q /tmp/qa --detach
  (cd /tmp/qa && git checkout -q --orphan qa-tmp && git rm -rqf . >/dev/null 2>&1 || true)
fi
rm -rf "/tmp/qa/$DEST" && mkdir -p "/tmp/qa/$DEST" && cp -R "$SRC"/. "/tmp/qa/$DEST/"
cd /tmp/qa
git add -A
git commit -qm "$MSG" || true
for i in 1 2 3; do git push -q origin HEAD:qa-results && break; sleep 5; git pull -q --rebase origin qa-results || true; done
