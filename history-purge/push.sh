#!/bin/bash
# Pushes the rewritten history of kaliberfinder and schiesstagebuch (deleted binaries
# purged, every image moved into Git LFS), then resets your clones in ~/src to it.
# - A branch is only overwritten if GitHub still has it at the commit the rewrite started
#   from (--force-with-lease). Each repo is pushed atomically: all of its branches move or none.
# - The LFS files are already uploaded to GitHub.
# Before running: allow force pushes on main in both repos (Settings > Branches > main).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-$HOME/src}
URL_BASE=${URL_BASE:-git@github.com:ravench}

KALIBERFINDER=(
  claude/project-thread-4oyhzw 4fe805c98fd58e14d6580e70dfd591a6924db7e8 d3205b673e7f20e080619019d86591072952a369 \
  claude/project-thread-yef595 9b51372282cabb54b7c73f4855bf5ba7a5d15696 b5d7a62fbb2b78c3cecaeb8af82c77b50f2e169b \
  claude/project-thread-zbstt4 5c62a8fcd7f3e8c391572e4ce65e43614945b0b5 cc8256784b38077224a0c2f49407fea81055ab34 \
  main 133e63b4c7dc14597b6a2fec26e6953ff5b53c3d 49ca9effa0dfe87cad8ab897cfa386fb30d2df47
)
KALIBERFINDER_DELETE="claude/project-thread-4qgyzg 1d667322194ae28042fbb9eff54635e216726900"
KALIBERFINDER_KEEP="pr-screens"

SCHIESSTAGEBUCH=(
  claude/project-thread-4krox9 5058ecd09eb617159bc660390ddd98df4909626f deab2144e30716d92dec1817de818cf10503cbb6 \
  claude/project-thread-4oyhzw 37116ca67f45df11b7b3eef21c2271bb2fc37d66 d36fe4f532439a23bc79befd69493196199fbd84 \
  claude/project-thread-rbd2n9 65e973899f9724e7778c21bfe7b72370fffee10a d2c6cc0794b4a0fb7789c0c558ae87abaef2ef50 \
  main cc85ca0e938bd46e8991213fc2bedda8759ae77b 94c4737c25f758b0a62e60961dab20a4afa67ce0
)
SCHIESSTAGEBUCH_DELETE="claude/project-thread-4qgyzg ef5e50e49e47a4edbe81d40fea989990ec0ac768"
SCHIESSTAGEBUCH_KEEP="ipad-screens pr-screens range-data range-distance-check"

die() { echo "STOPPED: $*" >&2; exit 1; }

git lfs version >/dev/null 2>&1 || die "git-lfs is missing. Run: brew install git-lfs && git lfs install"

check_clone() { # refuse to touch a clone with local work
  local d=$SRC/$1
  [ -d "$d/.git" ] || { echo "No clone at $d, so there is nothing to reset there."; return 0; }
  git -C "$d" fetch -q origin
  [ -z "$(git -C "$d" status --porcelain --untracked-files=no)" ] || die "$d has uncommitted changes. Commit or stash them first."
  [ -z "$(git -C "$d" log --branches --not --remotes --oneline)" ] || die "$d has commits that are on no remote branch."
}

push_repo() { # repo, delete spec, keep list, then triples of branch old new
  local repo=$1 dele=$2 keep=$3; shift 3
  local url="$URL_BASE/$repo.git" new_git=$HERE/$repo-new.git
  local args=() specs=() expected=" "
  rm -rf "$new_git"
  git clone -q --bare "$HERE/$repo-rewritten.bundle" "$new_git"
  echo "$repo:"
  while [ $# -gt 0 ]; do
    local ref=$1 old=$2 new=$3; shift 3
    [ "$(git -C "$new_git" rev-parse "refs/heads/$ref")" = "$new" ] || die "the $repo bundle has the wrong $ref"
    args+=("--force-with-lease=refs/heads/$ref:$old"); specs+=("+$new:refs/heads/$ref"); expected+="$ref "
    printf '  rewrite %-30s %s -> %s\n' "$ref" "${old:0:10}" "${new:0:10}"
  done
  local remote; remote=$(git ls-remote --heads "$url")
  if [ -n "$dele" ]; then
    set -- $dele
    local now; now=$(printf '%s\n' "$remote" | awk -v r="refs/heads/$1" '$2 == r {print $1}')
    if [ "$now" = "$2" ]; then args+=("--force-with-lease=refs/heads/$1:$2"); specs+=(":refs/heads/$1"); expected+="$1 "
      printf '  delete  %-30s (merged, old history)\n' "$1"
    elif [ -n "$now" ]; then die "$repo branch $1 moved to $now"; fi
  fi
  while read -r sha name; do
    name=${name#refs/heads/}
    case "$expected" in *" $name "*) continue ;; esac
    case " $keep " in *" $name "*) continue ;; esac
    die "$repo has a branch this script does not know: $name (it may carry the old history). Ask Claude."
  done <<< "$remote"
  PUSH_ARGS=("${args[@]}"); PUSH_SPECS=("${specs[@]}"); PUSH_GIT=$new_git; PUSH_URL=$url
}

reset_clone() {
  local d=$SRC/$1 b head
  [ -d "$d/.git" ] || return 0
  echo "Resetting $d to the new history"
  git -C "$d" fetch -q --prune origin
  head=$(git -C "$d" symbolic-ref -q --short HEAD || true)
  for b in $(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads); do
    if git -C "$d" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      if [ "$head" = "$b" ]; then git -C "$d" reset -q --hard "origin/$b"; else git -C "$d" branch -q -f "$b" "origin/$b"; fi
    elif [ "$head" != "$b" ]; then
      git -C "$d" branch -q -D "$b"   # it had no unpushed commits (checked before the push)
    fi
  done
  git -C "$d" lfs pull
  git -C "$d" reflog expire --expire=now --all
  git -C "$d" gc -q --prune=now
  echo "  now at $(git -C "$d" log -1 --format='%h %s')"
}

for repo in kaliberfinder schiesstagebuch; do check_clone $repo; done
push_repo kaliberfinder "$KALIBERFINDER_DELETE" "$KALIBERFINDER_KEEP" "${KALIBERFINDER[@]}"
KF_ARGS=("${PUSH_ARGS[@]}"); KF_SPECS=("${PUSH_SPECS[@]}"); KF_GIT=$PUSH_GIT; KF_URL=$PUSH_URL
push_repo schiesstagebuch "$SCHIESSTAGEBUCH_DELETE" "$SCHIESSTAGEBUCH_KEEP" "${SCHIESSTAGEBUCH[@]}"
SB_ARGS=("${PUSH_ARGS[@]}"); SB_SPECS=("${PUSH_SPECS[@]}"); SB_GIT=$PUSH_GIT; SB_URL=$PUSH_URL
echo "Untouched: pr-screens, ipad-screens, range-data, range-distance-check."
read -r -p "Type yes to force-push the branches above: " answer
[ "$answer" = yes ] || die "nothing pushed."

echo "== kaliberfinder"
git -C "$KF_GIT" push --atomic --no-verify "${KF_ARGS[@]}" "$KF_URL" "${KF_SPECS[@]}"
echo "== schiesstagebuch"
git -C "$SB_GIT" push --atomic --no-verify "${SB_ARGS[@]}" "$SB_URL" "${SB_SPECS[@]}"
rm -rf "$KF_GIT" "$SB_GIT"
for repo in kaliberfinder schiesstagebuch; do reset_clone $repo; done
echo "Done. Switch force pushes on main off again in both repos, then tell Claude."
echo "This folder can go afterwards: rm -rf \"$HERE\""
