#!/usr/bin/env bash
# Shared helpers for the vfox#335 probe. Source this file; do not run it.

section() { printf '\n\n########## %s\n' "$*"; }

is_windows() { case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) return 0 ;; *) return 1 ;; esac; }

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
    w=$(cygpath -w "$(cygpath -u "$p")" 2>/dev/null || echo "$p")
    echo "link: $w"
    powershell.exe -NoProfile -NonInteractive -Command \
      "\$i = Get-Item -LiteralPath '$w' -Force -ErrorAction SilentlyContinue; if (\$i) { 'attributes=' + \$i.Attributes + ' linktype=' + \$i.LinkType + ' target=' + (\$i.Target -join ';') } else { 'link does not exist' }" 2>&1 | tr -d '\r'
  else
    echo "link: $p -> $(readlink "$p" 2>/dev/null || echo '(not a symlink)')"
  fi
}


# PATH entries that matter for java, with their position in the list.
path_diag() {
  echo "PATH entries that mention java/jdk/vfox (position: entry), of $(printf '%s\n' "$PATH" | tr ':' '\n' | wc -l) in total:"
  printf '%s\n' "$PATH" | tr ':' '\n' | nl -ba | grep -i -E 'java|jdk|temurin|hostedtoolcache|\.vfox|\.version-fox' | head -20
}

# The same list the way a native Windows program (vfox.exe) sees it, before any hook touched it.
winpath_diag() {
  if is_windows; then
    echo "Windows-form PATH as native programs see it (position: entry):"
    MSYS_NO_PATHCONV=1 cmd.exe /c "echo %PATH%" | tr -d '\r' | tr ';' '\n' | nl -ba | grep -i -E 'java|jdk|temurin|hostedtoolcache|\.vfox|\.version-fox' | head -20
  fi
}

# What a user would add to .bashrc to keep vfox entries out of the incoming PATH.
strip_vfox_from_path() {
  PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -E '/\.(vfox|version-fox)(/|$)' | paste -sd: -)
  export PATH
}

show() {
  printf '\n--- %s\n' "$1"
  echo "JAVA_HOME=[$JAVA_HOME]"
  linkinfo
  echo "command -v java: $(command -v java)"
  echo "type -a java (first 3):"
  type -a java 2>&1 | sed -n '1,3p'
  echo "java -version: $(java -version 2>&1 | head -1)"
  local jc="$JAVA_HOME/bin/java"
  if [ -x "$jc" ]; then
    echo "\$JAVA_HOME/bin/java -version (what gradlew runs): $("$jc" -version 2>&1 | head -1)"
  else
    echo "\$JAVA_HOME/bin/java is not executable per [ -x ]"
  fi
  path_diag
}

# Needs GRADLE (unix path of the gradle start script) and GRADLE_PROJECT.
gradle_jv() {
  [ -n "$GRADLE" ] || return 0
  echo "[gradle] jv: $(cd "$GRADLE_PROJECT" && timeout 300 "$GRADLE" -q --console=plain jv 2>&1 | tail -3 | tr '\n' ' ')"
}

gradle_jv_nodaemon() {
  [ -n "$GRADLE" ] || return 0
  echo "[gradle --no-daemon] jv: $(cd "$GRADLE_PROJECT" && timeout 300 "$GRADLE" -q --console=plain --no-daemon jv 2>&1 | tail -3 | tr '\n' ' ')"
}

gradle_stop() {
  [ -n "$GRADLE" ] || return 0
  (cd "$GRADLE_PROJECT" && timeout 120 "$GRADLE" --stop 2>&1 | tail -2)
}

env_banner() {
  section "environment"
  uname -a
  echo "BASH_VERSION=$BASH_VERSION MSYSTEM=$MSYSTEM OSTYPE=$OSTYPE"
  echo "HOME=$HOME"
  echo "command -v bash: $(command -v bash)"
  vfox --version
}
