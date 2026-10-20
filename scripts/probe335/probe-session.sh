#!/usr/bin/env bash
# vfox#335 probe, scenario S: session-scope `vfox use` in a fresh bash that ran `vfox activate bash`.
# Usage: probe-session.sh <majorA> <majorB>
# Environment: GRADLE (unix path to the gradle start script) and GRADLE_PROJECT are optional.
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

A=${1:?majorA}
B=${2:?majorB}

env_banner

section "activate (what .bashrc does)"
eval "$("$VFOX" activate bash)"
echo "PROMPT_COMMAND=[${PROMPT_COMMAND[*]}]"
echo "__VFOX_SHELL=[$__VFOX_SHELL] __VFOX_PID=[$__VFOX_PID] __VFOX_CURTMPPATH=[$__VFOX_CURTMPPATH]"
prompt
show "S0: after activate and the first prompt, nothing selected yet"

section "vfox use java@$A (session) + prompt"
$TIMEOUT 120 "$VFOX" use java@"$A"
prompt
show "S1: after use $A"
gradle_jv

section "vfox use java@$B (session) + prompt"
$TIMEOUT 120 "$VFOX" use java@"$B"
prompt
show "S2: after use $B"
gradle_jv

section "vfox use java@$A (session), prompt NOT run"
$TIMEOUT 120 "$VFOX" use java@"$A"
show "S3: after use $A, the hook has not run yet"
gradle_jv
prompt
show "S4: after the next prompt"
gradle_jv

if [ -n "$GRADLE" ]; then
  section "same session, Gradle workarounds"
  gradle_jv_nodaemon
  gradle_stop
  gradle_jv
  gradle_stop
fi

section "done"
