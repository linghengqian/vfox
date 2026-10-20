#!/usr/bin/env bash
# vfox#335 probe, scenario G part 3: like part 2, but the shell first drops vfox entries from the incoming PATH
# (the workaround one would put in .bashrc before `eval "$(vfox activate bash)"`).
# Usage: probe-global-3.sh <majorB>
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

B=${1:?majorB}

env_banner
winpath_diag

section "strip vfox entries from PATH, then activate"
strip_vfox_from_path
path_diag
eval "$(vfox activate bash)"
prompt
show "W0: new shell, workaround, global choice only"

section "vfox use java@$B (session) + prompt"
timeout 120 vfox use java@"$B"
prompt
show "W1: workaround, session $B on top of the global choice"

section "done"
