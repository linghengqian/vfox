#!/usr/bin/env bash
# Shared helpers for the vfox#335 probe. Source this file; do not run it.

# Tools by absolute path: a PATH that vfox has broken (one of the things under test) must not blind the diagnostics.
UNAME=/usr/bin/uname
TR=/usr/bin/tr
NL=/usr/bin/nl
GREP=/usr/bin/grep
SED=/usr/bin/sed
WC=/usr/bin/wc
HEAD=/usr/bin/head
PASTE=/usr/bin/paste
TIMEOUT=/usr/bin/timeout
CYGPATH=/usr/bin/cygpath
# vfox as resolved before any hook has touched PATH.
VFOX=$(command -v vfox)

section() { printf '\n\n########## %s\n' "$*"; }

is_windows() { case "$($UNAME -s)" in MINGW* | MSYS* | CYGWIN*) return 0 ;; *) return 1 ;; esac; }

if is_windows; then
  SYS32=$($CYGPATH -u "$SYSTEMROOT\\System32")
  CMD_EXE=$SYS32/cmd.exe
  PS_EXE=$SYS32/WindowsPowerShell/v1.0/powershell.exe
fi

# What an interactive prompt does: PROMPT_COMMAND runs _vfox_hook before PS1 is printed.
prompt() {
  if declare -F _vfox_hook >/dev/null; then
    _vfox_hook
  else
    echo "!! _vfox_hook is not defined"
  fi
}

linkinfo() {
  # Print where the directory JAVA_HOME names really points to.
  local p=$JAVA_HOME
  [ -n "$p" ] || { echo "link: JAVA_HOME is empty"; return; }
  if is_windows; then
    local w
    w=$($CYGPATH -w "$($CYGPATH -u "$p")" 2>/dev/null || echo "$p")
    echo "link: $w"
    "$PS_EXE" -NoProfile -NonInteractive -Command \
      "\$i = Get-Item -LiteralPath '$w' -Force -ErrorAction SilentlyContinue; if (\$i) { 'attributes=' + \$i.Attributes + ' linktype=' + \$i.LinkType + ' target=' + (\$i.Target -join ';') } else { 'link does not exist' }" 2>&1 | $TR -d '\r'
  else
    echo "link: $p -> $(readlink "$p" 2>/dev/null || echo '(not a symlink)')"
  fi
}

# PATH entries that matter for java, with their position in the list.
path_diag() {
  echo "PATH entries that mention java/jdk/vfox (position: entry), of $(printf '%s\n' "$PATH" | $TR ':' '\n' | $WC -l) in total:"
  printf '%s\n' "$PATH" | $TR ':' '\n' | $NL -ba | $GREP -i -E 'java|jdk|temurin|hostedtoolcache|\.vfox|\.version-fox' | $HEAD -20
  echo "first 3 PATH entries: $(printf '%s\n' "$PATH" | $TR ':' '\n' | $HEAD -3 | $TR '\n' ' ')"
}

# The same list the way a native Windows program (vfox.exe) sees it, before any hook touched it.
winpath_diag() {
  if is_windows; then
    echo "Windows-form PATH as native programs see it (position: entry):"
    MSYS_NO_PATHCONV=1 "$CMD_EXE" /c "echo %PATH%" | $TR -d '\r' | $TR ';' '\n' | $NL -ba | $GREP -i -E 'java|jdk|temurin|hostedtoolcache|\.vfox|\.version-fox' | $HEAD -20
  fi
}

# What a user would add to .bashrc to keep vfox entries out of the incoming PATH.
strip_vfox_from_path() {
  PATH=$(printf '%s' "$PATH" | $TR ':' '\n' | $GREP -v -E '/\.(vfox|version-fox)(/|$)' | $PASTE -sd: -)
  export PATH
}

show() {
  printf '\n--- %s\n' "$1"
  echo "JAVA_HOME=[$JAVA_HOME]"
  linkinfo
  echo "vfox by name: $(command -v vfox || echo 'NOT FOUND')   ls by name: $(command -v ls || echo 'NOT FOUND')"
  echo "command -v java: $(command -v java || echo 'NOT FOUND')"
  echo "type -a java (first 3):"
  type -a java 2>&1 | $HEAD -3
  echo "java -version: $(java -version 2>&1 | $HEAD -1)"
  local jc="$JAVA_HOME/bin/java"
  if [ -x "$jc" ]; then
    echo "\$JAVA_HOME/bin/java -version (what gradlew runs): $("$jc" -version 2>&1 | $HEAD -1)"
  else
    echo "\$JAVA_HOME/bin/java is not executable per [ -x ]"
  fi
  path_diag
}

# Needs GRADLE (unix path of the gradle start script) and GRADLE_PROJECT.
gradle_jv() {
  [ -n "$GRADLE" ] || return 0
  echo "[gradle] jv: $(cd "$GRADLE_PROJECT" && $TIMEOUT 300 "$GRADLE" -q --console=plain jv 2>&1 | tail -3 | $TR '\n' ' ')"
}

gradle_jv_nodaemon() {
  [ -n "$GRADLE" ] || return 0
  echo "[gradle --no-daemon] jv: $(cd "$GRADLE_PROJECT" && $TIMEOUT 300 "$GRADLE" -q --console=plain --no-daemon jv 2>&1 | tail -3 | $TR '\n' ' ')"
}

gradle_stop() {
  [ -n "$GRADLE" ] || return 0
  (cd "$GRADLE_PROJECT" && $TIMEOUT 120 "$GRADLE" --stop 2>&1 | tail -2)
}

env_banner() {
  section "environment"
  $UNAME -a
  echo "BASH_VERSION=$BASH_VERSION MSYSTEM=$MSYSTEM OSTYPE=$OSTYPE"
  echo "HOME=$HOME"
  echo "command -v bash: $(command -v bash)"
  echo "cygdrive/MSYS drive prefix check: /c exists=$([ -d /c ] && echo yes || echo no), /cygdrive/c exists=$([ -d /cygdrive/c ] && echo yes || echo no)"
  "$VFOX" --version
}
