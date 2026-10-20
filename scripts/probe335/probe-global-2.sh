#!/usr/bin/env bash
# vfox#335 probe, scenario G part 2: a NEW shell whose environment carries the global choice, then a session `use`.
# Usage: probe-global-2.sh <majorB>
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

B=${1:?majorB}

env_banner
echo "inherited JAVA_HOME=[$JAVA_HOME]"
echo "inherited hook variables: __VFOX_SHELL=[$__VFOX_SHELL] __VFOX_PID=[$__VFOX_PID] __VFOX_CURTMPPATH=[$__VFOX_CURTMPPATH]"
echo "java before activation: $(command -v java) -> $(java -version 2>&1 | head -1)"

section "activate (what .bashrc does)"
eval "$(vfox activate bash)"
prompt
show "G0: new shell, global choice only"
gradle_jv

section "vfox use java@$B (session) + prompt"
timeout 120 vfox use java@"$B"
prompt
show "G1: session $B on top of the global choice"
gradle_jv
gradle_jv_nodaemon
gradle_stop

section "done"
