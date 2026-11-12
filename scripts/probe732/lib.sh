#!/usr/bin/env bash
# Shared helpers for the vfox#732 probe. Source this file; do not run it.

section() { printf '\n\n########## %s\n' "$*"; }

# What an interactive prompt does: PROMPT_COMMAND runs _vfox_hook before PS1 is printed.
prompt() {
  if declare -F _vfox_hook >/dev/null; then
    _vfox_hook
  else
    echo "!! _vfox_hook is not defined"
  fi
}

java_major() {
  java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/'
}

show_java() {
  local label=$1
  section "$label"
  echo "JAVA_HOME=[$JAVA_HOME]"
  echo "command -v java: $(command -v java)"
  echo "type -a java (first 3):"
  type -a java 2>&1 | sed -n '1,3p'
  echo "java -version: $(java -version 2>&1 | head -1)"
  if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    echo "\$JAVA_HOME/bin/java -version: $("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
  fi
  echo "vfox config path.mode: $(vfox config path.mode 2>&1 | tr -d '\r')"
  echo "PATH entries that mention java/vfox ($(printf '%s\n' "$PATH" | tr ':' '\n' | wc -l | tr -d ' ') total):"
  printf '%s\n' "$PATH" | tr ':' '\n' | nl -ba | grep -i -E 'java|jdk|temurin|hostedtoolcache|\.vfox|\.version-fox' | head -12
}

expect_java() {
  local want=$1 label=$2 got
  got=$(java_major)
  if [ "$got" = "$want" ]; then
    echo "PROBE OK: $label: java reports major $got"
    return 0
  fi
  echo "PROBE FAIL: $label: java reports major ${got:-<none>}, want $want"
  return 1
}
