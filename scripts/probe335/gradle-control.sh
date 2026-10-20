#!/usr/bin/env bash
# vfox#335 probe: does a Gradle daemon follow a JAVA_HOME junction that is re-pointed? No vfox involved.
# Usage: gradle-control.sh <windows path of JDK A> <windows path of JDK B>
# Environment: GRADLE (unix path of the gradle start script), GRADLE_PROJECT (dir with the `jv` task).
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

A_HOME=${1:?JDK A}
B_HOME=${2:?JDK B}
J='C:\probe\jdkcur'

retarget() {
  MSYS_NO_PATHCONV=1 cmd.exe /c "if exist $J rmdir $J"
  powershell.exe -NoProfile -NonInteractive -Command \
    "New-Item -ItemType Junction -Path '$J' -Target '$1' | Out-Null; \$i = Get-Item -LiteralPath '$J'; 'junction $J -> ' + (\$i.Target -join ';')" | tr -d '\r'
}

jvm_info() {
  echo "[$1] \$JAVA_HOME/bin/java: $("$JAVA_HOME/bin/java" -XshowSettings:properties -version 2>&1 | grep -E '^\s+(java.home|java.version) =' | tr -s ' ' | tr '\n' ' ')"
}

env_banner
echo "A=$A_HOME"
echo "B=$B_HOME"
mkdir -p /c/probe

section "JAVA_HOME is the junction $J, pointing at A"
retarget "$A_HOME"
export JAVA_HOME="$J"
jvm_info A
echo "[gradle --version] $(cd "$GRADLE_PROJECT" && "$GRADLE" --version 2>&1 | grep -E 'Launcher JVM|Daemon JVM' | tr '\n' ' ')"
gradle_jv

section "the junction is re-pointed at B (nothing else changes)"
retarget "$B_HOME"
jvm_info B
echo "[gradle --version] $(cd "$GRADLE_PROJECT" && "$GRADLE" --version 2>&1 | grep -E 'Launcher JVM|Daemon JVM' | tr '\n' ' ')"
gradle_jv
gradle_jv_nodaemon

section "gradle --stop, then the same build again"
gradle_stop
gradle_jv

section "done"
