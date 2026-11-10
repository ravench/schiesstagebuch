#!/bin/bash
# Moves the old screens branches out of kaliberfinder and schiesstagebuch into ravench/app-screens.
# 1. Copies them there with the same commit IDs, so the image links in old PR comments can point there.
# 2. Once main in an app repo pushes its screens to app-screens (kaliberfinder #84, schiesstagebuch #117),
#    deletes the old branches from that repo, after you type "yes".
# Safe to run more than once: before the PRs are merged it only copies.
set -euo pipefail
URL_BASE=${URL_BASE:-git@github.com:ravench}
SCREENS="$URL_BASE/app-screens.git"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q --bare "$work/r.git"
cd "$work/r.git"

sha_of() { git ls-remote "$1" "refs/heads/$2" | cut -f1; }

# app, its branch, the branch in app-screens, the workflow on main that must use app-screens first
MOVES=(
  "kaliberfinder pr-screens archive/kaliberfinder-pr-screens .github/workflows/build.yml"
  "schiesstagebuch pr-screens archive/schiesstagebuch-pr-screens .github/workflows/build.yml"
  "schiesstagebuch ipad-screens schiesstagebuch/ipad-screens .github/workflows/ipad-screens.yml"
)

echo "== Copy to app-screens"
to_delete=()
for move in "${MOVES[@]}"; do
  read -r app branch target workflow <<<"$move"
  url="$URL_BASE/$app.git"
  sha=$(sha_of "$url" "$branch")
  if [ -z "$sha" ]; then echo "$app $branch: already gone"; continue; fi
  there=$(sha_of "$SCREENS" "$target")
  if [ "$there" = "$sha" ]; then
    echo "$app $branch: already in app-screens as $target (${sha:0:7})"
  elif [ -n "$there" ] && [ "$branch" = ipad-screens ]; then
    # Only the latest iPad set is kept, and the new workflow has already published a newer one.
    echo "$app $branch: app-screens has a newer $target, the old set is not copied"
  else
    git fetch -q "$url" "refs/heads/$branch:refs/heads/$target"
    # No force: an archive that is already there may only move forward.
    git push -q "$SCREENS" "refs/heads/$target:refs/heads/$target"
    [ "$(sha_of "$SCREENS" "$target")" = "$sha" ] || { echo "STOPPED: $target in app-screens is not at $sha"; exit 1; }
    echo "$app $branch: copied to app-screens as $target (${sha:0:7}, $(git rev-list --count "$target") commits)"
  fi
  git fetch -q --depth 1 "$url" main
  if git show "FETCH_HEAD:$workflow" | grep -q 'SCREENS_REPO: ravench/app-screens'; then
    to_delete+=("$app $branch $sha")
  else
    echo "   $app main still pushes its screens to $branch: delete it after the PR is merged (run this again)"
  fi
done

if ! git ls-remote --exit-code "$SCREENS" refs/heads/main >/dev/null; then
  blob=$(git hash-object -w --stdin <<'README'
# app-screens

Screenshots that the CI of [ravench/kaliberfinder](https://github.com/ravench/kaliberfinder) and
[ravench/schiesstagebuch](https://github.com/ravench/schiesstagebuch) takes. They live here so the
app repositories' history stays small.

- `kaliberfinder/pr-screens`, `schiesstagebuch/pr-screens`: one folder per pull request with the
  screens that look different, before and after. The *PR screens* comment on each pull request
  links them by commit.
- `schiesstagebuch/ipad-screens`: the latest run of the *iPad screens* workflow.
- `archive/kaliberfinder-pr-screens`, `archive/schiesstagebuch-pr-screens`: the old `pr-screens`
  branches of the app repositories (until 6 November 2026), same commits. Older comments link here.

The images are plain files, not Git LFS: the comments link them through raw.githubusercontent.com,
which does not serve LFS files. Do not delete or rewrite these branches, or the images in old
comments break. The workflows push with the deploy key stored in each app repository's
`SCREENS_DEPLOY_KEY` secret.
README
)
  tree=$(printf '100644 blob %s\tREADME.md\n' "$blob" | git mktree)
  commit=$(git commit-tree "$tree" -m "Describe the screens branches" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NTkWWMzq3E7VrKT5P13kqc")
  if git push -q "$SCREENS" "$commit:refs/heads/main"; then echo "app-screens: added README.md on main"
  else echo "app-screens: could not add README.md on main (not needed for the move)"; fi
fi

[ ${#to_delete[@]} -gt 0 ] || { echo "Nothing to delete yet."; exit 0; }
echo
echo "== Delete from the app repos (their copies are in app-screens):"
for d in "${to_delete[@]}"; do read -r app branch sha <<<"$d"; echo "   $app: $branch (${sha:0:7})"; done
read -r -p "Type yes to delete them: " answer
[ "$answer" = yes ] || { echo "Nothing deleted."; exit 0; }
for d in "${to_delete[@]}"; do
  read -r app branch sha <<<"$d"
  git push -q --force-with-lease="refs/heads/$branch:$sha" "$URL_BASE/$app.git" ":refs/heads/$branch"
  [ -z "$(sha_of "$URL_BASE/$app.git" "$branch")" ] || { echo "STOPPED: $app $branch is still there"; exit 1; }
  echo "   $app: deleted $branch"
done
echo "Done. In your clones, 'git fetch --prune' drops the old origin/pr-screens and origin/ipad-screens refs."
