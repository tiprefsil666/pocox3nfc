# Shared functions: logging, and the small checks every script needs.
#
# Sourced after env.sh.

# Colours, but only on a terminal.
if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
    C_RESET=; C_BOLD=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=
fi

say()  { printf '%s==%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
note() { printf '     %s\n' "$*"; }
warn() { printf '%satenção%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
bad()  { printf '%sFALHA%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { printf '%serro%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# Run a command, or stop with the command printed.
run() {
    printf '%s$ %s%s\n' "$C_BOLD" "$*" "$C_RESET"
    "$@" || die "failed: $*"
}

# Does this file exist and is it not empty?
have() { [ -s "$1" ]; }

# The tool that found a command, or nothing.
which_of() { command -v "$1" 2>/dev/null; }

# Load env.sh and lib.sh from anywhere.
_load_env() {
    . "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
    . "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
}
