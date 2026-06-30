#!/usr/bin/env bash
# Git merge driver: auto-resolve __manifest__.py VERSION-LINE conflicts by picking the
# higher version; leave EVERY other conflict for a human (ST-P1-74).
#
# Why: on a shared Odoo branch a pre-commit hook bumps `version` on every commit, so each
# rebase onto origin conflicts on that one line (my `.207` vs origin `.206`). That conflict
# is mechanical — the answer is always "take the higher version" — yet it stalls every
# rebase-retry of a contended push.
#
# SAFE BY CONSTRUCTION: a hunk is auto-resolved ONLY when BOTH sides are exactly one line
# AND both are a `version` key line. Anything else (multi-line hunk, a non-version line, a
# version line tangled with other edits) is left as a normal conflict and the driver exits
# non-zero, so git reports the file as conflicted for manual resolution. It can never
# silently drop a real code change.
#
# Install (per clone):
#   git config merge.odoo-manifest-version.name "Odoo __manifest__.py version max-merge"
#   git config merge.odoo-manifest-version.driver "/abs/path/odoo-manifest-version-merge.sh %O %A %B"
#   echo '**/__manifest__.py merge=odoo-manifest-version' >> .gitattributes   # or .git/info/attributes
#
# Args (git passes): %O = ancestor, %A = current/ours (also the OUTPUT file), %B = theirs.
set -u

O="${1:?merge driver: missing %O}"; A="${2:?merge driver: missing %A}"; B="${3:?missing %B}"

# Pattern for an Odoo manifest version key line, e.g.   'version': '17.0.1.0.207',
vpat=$'^[[:space:]]*[\x27"]version[\x27"][[:space:]]*:'

is_version_line() { [[ "$1" =~ $vpat ]]; }

version_value() {  # extract the X.Y.Z string from a version line
  printf '%s\n' "$1" | sed -n "s/.*[\"']version[\"'][[:space:]]*:[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p"
}

# 3-way merge into stdout with labelled conflict markers. Exit 0 == clean.
merged="$(git merge-file -p -L ours -L base -L theirs "$A" "$O" "$B" 2>/dev/null)"
mf_status=$?
if [ "$mf_status" -eq 0 ]; then
  printf '%s' "$merged" > "$A"
  exit 0
fi
if [ "$mf_status" -lt 0 ]; then
  exit 1   # merge-file error — do not touch the file, leave it for the human
fi

out=""; unresolved=0; state=normal
ours=(); theirs=()
flush_conflict_verbatim() {
  unresolved=1
  out+='<<<<<<< ours'$'\n'
  local l; for l in "${ours[@]}"; do out+="$l"$'\n'; done
  out+='======='$'\n'
  for l in "${theirs[@]}"; do out+="$l"$'\n'; done
  out+='>>>>>>> theirs'$'\n'
}
while IFS= read -r line || [ -n "$line" ]; do
  case "$state" in
    normal)
      if [[ "$line" == '<<<<<<<'* ]]; then state=ours; ours=(); theirs=(); continue; fi
      out+="$line"$'\n'
      ;;
    ours)
      if [[ "$line" == '======='* ]]; then state=theirs; continue; fi
      ours+=("$line")
      ;;
    theirs)
      if [[ "$line" == '>>>>>>>'* ]]; then
        if [ "${#ours[@]}" -eq 1 ] && [ "${#theirs[@]}" -eq 1 ] \
           && is_version_line "${ours[0]}" && is_version_line "${theirs[0]}"; then
          ov="$(version_value "${ours[0]}")"; tv="$(version_value "${theirs[0]}")"
          if [ -n "$ov" ] && [ -n "$tv" ]; then
            hi="$(printf '%s\n%s\n' "$ov" "$tv" | sort -V | tail -1)"
            if [ "$hi" = "$tv" ] && [ "$tv" != "$ov" ]; then
              out+="${theirs[0]}"$'\n'   # theirs strictly higher -> take theirs line
            else
              out+="${ours[0]}"$'\n'     # ours higher or equal -> keep ours
            fi
          else
            flush_conflict_verbatim       # could not parse a version value -> leave conflict
          fi
        else
          flush_conflict_verbatim
        fi
        state=normal; continue
      fi
      theirs+=("$line")
      ;;
  esac
done <<< "$merged"

printf '%s' "$out" > "$A"
[ "$unresolved" -eq 0 ]
