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
# AND that line is the `version` key AND NOTHING ELSE (key, quoted value, optional trailing
# comma, end-of-line). A multi-line hunk, a non-version line, a version line that ALSO
# carries another key (`'version': '..', 'auto_install': False,`), or an unparseable version
# is left as a normal conflict and the driver exits non-zero, so git reports the file
# conflicted for manual resolution. It can never silently drop a real code change. It also
# operates on a COPY of %A, so a `git merge-file` error never corrupts or truncates the file.
#
# Install (per clone):
#   git config merge.odoo-manifest-version.name "Odoo __manifest__.py version max-merge"
#   git config merge.odoo-manifest-version.driver "/abs/path/odoo-manifest-version-merge.sh %O %A %B"
#   echo '**/__manifest__.py merge=odoo-manifest-version' >> .gitattributes   # or .git/info/attributes
#
# Args (git passes): %O = ancestor, %A = current/ours (also the OUTPUT file), %B = theirs.
set -u

O="${1:?merge driver: missing %O}"; A="${2:?merge driver: missing %A}"; B="${3:?missing %B}"

# A version line and NOTHING else: e.g.   'version': '17.0.1.0.207',
vpat=$'^[[:space:]]*[\x27"]version[\x27"][[:space:]]*:[[:space:]]*[\x27"][^\x27"]*[\x27"][[:space:]]*,?[[:space:]]*$'
is_version_line() { [[ "$1" =~ $vpat ]]; }
version_value() {  # extract the X.Y.Z string from a version line
  printf '%s\n' "$1" | sed -n "s/.*[\"']version[\"'][[:space:]]*:[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p"
}

# Merge on a COPY so a merge-file error cannot corrupt/truncate %A (we then leave %A = ours
# for the human). `git merge-file` writes the result (or conflict markers) in place and
# returns 0 (clean), a positive conflict count, or 255 on error.
tmp="$(mktemp)" || exit 1
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT
cp -- "$A" "$tmp" || exit 1

git merge-file -q -L ours -L base -L theirs "$tmp" "$O" "$B"
status=$?
if [ "$status" -eq 0 ]; then
  cp -- "$tmp" "$A"            # clean merge — byte-exact (no command-substitution newline strip)
  exit 0
fi
if [ "$status" -lt 0 ] || [ "$status" -gt 128 ]; then
  exit 1                       # merge-file ERROR (e.g. 255) — leave %A = ours, report conflict
fi

# status = conflict count (1..128). Resolve version-only hunks; leave everything else.
out=""; unresolved=0; state=normal
ours=(); theirs=()
flush_conflict_verbatim() {
  unresolved=1
  out+='<<<<<<< ours'$'\n'
  local l
  for l in ${ours[@]+"${ours[@]}"};  do out+="$l"$'\n'; done
  out+='======='$'\n'
  for l in ${theirs[@]+"${theirs[@]}"}; do out+="$l"$'\n'; done
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
done < "$tmp"

printf '%s' "$out" > "$A"
[ "$unresolved" -eq 0 ]
