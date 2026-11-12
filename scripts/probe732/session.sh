#!/usr/bin/env bash
# vfox#732 probe, part 2: a NEW bash whose PATH carries the global choice from the
# registry (machine PATH with a system JDK, then the user PATH with vfox), then a
# session `vfox use java@<B>`.
# Usage: session.sh <majorB> <expectedGlobalMajor>
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

B=${1:?majorB}
G=${2:?globalMajor}

vfox --version
echo "inherited JAVA_HOME=[$JAVA_HOME]"
echo "global java before activation: $(command -v java) -> $(java -version 2>&1 | head -1)"

section "activate (what .bashrc does)"
eval "$(vfox activate bash)"
prompt
show_java "new shell, global choice only"
expect_java "$G" "global choice in a new shell"
global_rc=$?

section "vfox use java@$B (session) + prompt"
timeout 180 vfox use java@"$B"
echo "vfox use exit: $?"
prompt
show_java "session $B on top of the global choice"
expect_java "$B" "session choice"
session_rc=$?

if [ "$global_rc" -ne 0 ] || [ "$session_rc" -ne 0 ]; then
  exit 1
fi
exit 0
