#!/usr/bin/env bash
# Reproduces vfox-maven issue #8 against one plugin release.
#
# Usage: bash repro.sh <plugin.zip> <label> <version> <stale-version> <partial-version>
#
# Each case gets a HOME of its own. "same terminal" runs vfox use from a folder outside
# HOME, as the reporter's open window was. "new terminal" starts a login shell in HOME, as
# a new Terminal window does. Before each check the shell runs the precmd hooks that
# `vfox activate zsh` installs, as a prompt does, so PATH is what the prompt would give.
set -u

PLUGIN_SRC="$1"
LABEL="$2"
VERSION="$3"
STALE="$4"
PARTIAL="$5"
WORK="$(mktemp -d)"

cat > "$WORK/same.zsh" <<'EOF'
vfox use -g "$SPEC" 2>&1
for f in $precmd_functions; do $f; done
m=$(command -v mvn 2>/dev/null)
echo "mvn: ${m:-NOT_FOUND}"
mvn -v 2>&1 | head -n 1
EOF

cat > "$WORK/new.zsh" <<'EOF'
for f in $precmd_functions; do $f; done
m=$(command -v mvn 2>/dev/null)
echo "mvn: ${m:-NOT_FOUND}"
mvn -v 2>&1 | head -n 1
echo "PATH entries that mention maven: $(echo "$PATH" | tr ':' '\n' | grep -i maven | tr '\n' ' ')"
EOF

run_case() {
  case_name="$1"
  spec="$2"
  stale="$3"
  home="$(mktemp -d)"
  proj="$(mktemp -d)"
  printf '%s\n' 'eval "$(vfox activate zsh)"' > "$home/.zshrc"
  echo ""
  echo "=== [$LABEL] $case_name"
  (
    export HOME="$home"
    export SPEC="$spec"
    cd "$proj" || exit 1
    if ! vfox add --source "$PLUGIN_SRC" > "$WORK/add.log" 2>&1; then
      echo "  vfox add FAILED:"
      tail -n 8 "$WORK/add.log" | sed 's/^/    /'
      exit 0
    fi
    if ! vfox install "maven@$VERSION" > "$WORK/install.log" 2>&1; then
      echo "  vfox install maven@$VERSION FAILED:"
      tail -n 8 "$WORK/install.log" | sed 's/^/    /'
      exit 0
    fi
    if [ -n "$stale" ]; then
      printf '%s\n' "$stale" > "$home/.tool-versions"
      echo "  wrote \$HOME/.tool-versions: $stale"
    fi
    echo "  [same terminal, cwd outside HOME] vfox use -g $spec"
    zsh -i -c "source '$WORK/same.zsh'" 2>&1 | grep -v -E 'tty|job control' | sed 's/^/    /'
    echo "  [new terminal, cwd = HOME]"
    cd "$home" && zsh -l -i -c "source '$WORK/new.zsh'" 2>&1 | grep -v -E 'tty|job control' | sed 's/^/    /'
  )
}

echo "### plugin=$LABEL vfox=$(vfox --version 2>&1 | head -n 1) version=$VERSION stale=$STALE partial=$PARTIAL"
run_case "use -g maven@$VERSION" "maven@$VERSION" ""
run_case "use -g maven (no version)" "maven" ""
run_case "use -g maven@$PARTIAL (partial version)" "maven@$PARTIAL" ""
run_case "stale \$HOME/.tool-versions names maven $STALE, not installed" "maven@$VERSION" "maven $STALE"
run_case "control: stale \$HOME/.tool-versions names maven $VERSION, installed" "maven@$VERSION" "maven $VERSION"
echo "### done $LABEL"
