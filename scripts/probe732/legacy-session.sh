#!/usr/bin/env bash
# vfox#732 probe, control: the same new bash with path.mode=legacy (what vfox
# 1.0.x did). The system JDK in the machine PATH is expected to win again,
# which shows that this probe would catch the reported bug.
# Usage: legacy-session.sh <majorB> <systemMajor>
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

B=${1:?majorB}
SYS=${2:?systemMajor}

vfox --version
echo "vfox config path.mode: $(vfox config path.mode 2>&1 | tr -d '\r')"
echo "inherited JAVA_HOME=[$JAVA_HOME]"

section "activate (what .bashrc does)"
eval "$(vfox activate bash)"
prompt
show_java "legacy: new shell, global choice only"

section "vfox use java@$B (session) + prompt"
timeout 180 vfox use java@"$B"
echo "vfox use exit: $?"
prompt
show_java "legacy: session $B on top of the global choice"
expect_java "$SYS" "legacy mode keeps the system java in front"
exit $?
