#!/bin/bash
# Pushes the screens that look different (the out dir of `pr_screens.py changes`) to this pull
# request's folder in ravench/app-screens, outside this repo's history, and adds or updates the
# pull request's comment for them. Both screens jobs of .github/workflows/build.yml run it:
#
#   bash publish_pr_screens.sh <changes dir>        # iPhone: <PR>/before, <PR>/after
#   bash publish_pr_screens.sh <changes dir> ipad   # iPad: <PR>/ipad/before, <PR>/ipad/after
#
# Environment: GH_TOKEN, REPO, PR, HEAD_SHA, RUN_URL, SCREENS_REPO, SCREENS_BRANCH, SCREENS_DEPLOY_KEY.
set -eo pipefail
TOOLS=$(cd "$(dirname "$0")" && pwd)
CHANGED=$(cd "$1" && pwd)
DEVICE=$2
DEST="$PR${DEVICE:+/$DEVICE}"
# ravench/app-screens accepts this repo's deploy key; the host key is GitHub's published one.
[ -n "$SCREENS_DEPLOY_KEY" ] || { echo "::error::The SCREENS_DEPLOY_KEY secret is missing"; exit 1; }
mkdir -p ~/.ssh && printf '%s\n' "$SCREENS_DEPLOY_KEY" > ~/.ssh/app-screens && chmod 600 ~/.ssh/app-screens
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" >> ~/.ssh/known_hosts
export GIT_SSH_COMMAND="ssh -i ~/.ssh/app-screens -o IdentitiesOnly=yes"
# Each pull request has its own folder on the branch; retry if another run pushed first.
for attempt in 1 2 3 4 5 fail; do
  [ "$attempt" != fail ] || { echo "Could not push to $SCREENS_REPO"; exit 1; }
  rm -rf branch && git init -q branch && cd branch
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git remote add origin "git@github.com:${SCREENS_REPO}.git"
  if git fetch -q --depth 1 origin "$SCREENS_BRANCH"; then git checkout -q -b screens FETCH_HEAD; else git checkout -q --orphan screens; fi
  # Only this device's screens: the other device's job keeps its own up to date.
  rm -rf "$DEST/before" "$DEST/after" && mkdir -p "$DEST" && cp -R "$CHANGED/before" "$CHANGED/after" "$DEST/"
  git add -A
  git commit -q --allow-empty -m "${DEVICE:-iPhone} screens for #$PR at $HEAD_SHA"
  git push -q origin "HEAD:refs/heads/$SCREENS_BRANCH" && break
  cd .. && sleep $((attempt * 3))
done
BASE_URL="https://raw.githubusercontent.com/${SCREENS_REPO}/$(git rev-parse HEAD)/$DEST"
cd ..
python3 "$TOOLS/pr_screens.py" comment "$CHANGED" "$BASE_URL" "$RUN_URL" $DEVICE > comment.md
# One comment per pull request and device (its marker is the first line), updated on every run.
MARKER=$(head -1 comment.md)
# --slurp: one array over all pages; `| head -1` would cut gh off mid-page and fail the pipeline (pipefail).
ID=$(gh api "repos/$REPO/issues/$PR/comments" --paginate --slurp \
  --jq "[.[][] | select(.body | startswith(\"$MARKER\"))][0].id // empty")
if [ -n "$ID" ]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$ID" -F body=@comment.md >/dev/null
else
  gh api "repos/$REPO/issues/$PR/comments" -F body=@comment.md >/dev/null
fi
