"""Shared pytest setup for the AI_AUTO framework suite.

Several tests copy `scripts/collect-review-context.sh` (and review-gate.sh / summarize)
into a throwaway temp repo and run it. Those scripts now source the single hardened-git
wrapper `scripts/git-harden.sh` (review_git, R6 local-config RCE fix). Rather than copy the
helper into each temp repo's working tree — which would pollute the changed/untracked file
set that the phase-scope and persona-lens context tests assert on — point the scripts at the
real engine helper via its resolution override. This is the same file the sibling lookup
would find in a real install, so behavior is identical and the project tree stays clean.
"""

import os
from pathlib import Path

_GIT_HARDEN = Path(__file__).resolve().parents[1] / "scripts" / "git-harden.sh"
os.environ.setdefault("AI_AUTO_GIT_HARDEN_SH", str(_GIT_HARDEN))
