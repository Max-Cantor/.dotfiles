#!/usr/bin/env bash
# nix-list.sh: Lists Nix packages from environment.systemPackages in a nix-darwin flake,
#              and optionally lists Homebrew packages.

# Immediately exit on errors, undefined variables, or pipe failures
set -euo pipefail
# Uncomment the next line for detailed command tracing if debugging is needed
# set -x 

# --- Configuration ---
# Path to your Nix flake directory
FLAKE_DIR="$HOME/.config/nix"
# --- End Configuration ---

# Function to show usage
usage() {
  # set +x # Turn off command tracing for usage message if set -x was active
  echo "Usage: $(basename "$0") <darwin-config-name> [package-name]"
  echo ""
  echo "  <darwin-config-name>: (Required) The name of your darwinConfiguration output"
  echo "                        in your flake.nix (e.g., 'maxIT')."
  echo "  [package-name]:       (Optional) If provided, lists all files installed by"
  echo "                        that Nix package. Homebrew listing is skipped in this case."
  echo ""
  echo "  If [package-name] is omitted, lists all Nix system packages and then all Homebrew packages."
  echo ""
  echo "  Examples:"
  echo "    $(basename "$0") maxIT             # Lists Nix system packages & Homebrew packages for 'maxIT' config"
  echo "    $(basename "$0") maxIT coreutils   # Lists files for Nix package 'coreutils' in 'maxIT' config"
  echo ""
  echo "  Flake directory used: $FLAKE_DIR"
  echo "  Requires: nix, jq"
  exit 1
}

# --- Argument Parsing ---
if [ $# -eq 0 ]; then
  echo "Error: Missing <darwin-config-name> argument." >&2
  usage
fi

DARWIN_CONFIG_NAME="$1"
shift # Remove the first argument, remaining args are for package-name

PACKAGE_ARG=""
if [ $# -gt 0 ]; then
  PACKAGE_ARG="$1"
  if [ $# -gt 1 ]; then # More than one package name arg
    echo "Error: Too many arguments. Only one [package-name] is allowed." >&2
    usage
  fi
fi

# --- Pre-flight checks ---
if ! command -v nix &> /dev/null; then
    echo "Error: 'nix' command not found. Please ensure Nix is installed and in your PATH." >&2
    exit 1 
fi

if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' command not found. This script requires jq." >&2
    echo "You can install it with Nix (e.g., via your flake) or 'nix-env -iA nixpkgs.jq'." >&2
    exit 1
fi

if [ ! -f "$FLAKE_DIR/flake.nix" ]; then
  echo "Error: Flake file not found at $FLAKE_DIR/flake.nix" >&2
  echo "Please check the FLAKE_DIR variable in this script." >&2
  exit 1
fi

# --- Get Nix Package Data ---
PROCESSED_NIX_PACKAGES_JSON="[]" # Default to an empty JSON array

FLAKE_ATTRIBUTE_PART="darwinConfigurations.\"$DARWIN_CONFIG_NAME\".config.environment.systemPackages"
FULL_FLAKE_REF="$FLAKE_DIR#$FLAKE_ATTRIBUTE_PART"

echo "--- Nix Packages ---" # User-facing header
# Inform user about the evaluation step (can be slow)
echo "Evaluating Nix packages from $FULL_FLAKE_REF (this may take a moment)..." >&2

NIX_EVAL_SYSTEM_PACKAGES_OUTPUT=$(nix eval --json --no-allow-import-from-derivation --impure "$FULL_FLAKE_REF" 2>&1)
NIX_EVAL_EXIT_CODE=$?

# Debug output (commented out by default)
# echo "Debug: NIX_EVAL_EXIT_CODE: $NIX_EVAL_EXIT_CODE" >&2
# echo "Debug: NIX_EVAL_SYSTEM_PACKAGES_OUTPUT (raw from nix eval):" >&2
# echo "$NIX_EVAL_SYSTEM_PACKAGES_OUTPUT" >&2 

if [ $NIX_EVAL_EXIT_CODE -ne 0 ]; then
  echo "Error evaluating flake attribute $FULL_FLAKE_REF for Nix packages:" >&2
  echo "$NIX_EVAL_SYSTEM_PACKAGES_OUTPUT" >&2
  PACKAGE_STORE_PATHS_ARGS="" # Ensure this is empty so Nix listing shows error/nothing
else
  JQ_NIX_PATHS_OUTPUT=$(echo "$NIX_EVAL_SYSTEM_PACKAGES_OUTPUT" | jq -r '.[]')
  # Debug output (commented out by default)
  # echo "Debug: JQ_NIX_PATHS_OUTPUT (direct from jq -r '.[]', should be one path per line):" >&2
  # echo "---BEGIN JQ_NIX_PATHS_OUTPUT---" >&2
  # echo "$JQ_NIX_PATHS_OUTPUT" >&2 
  # echo "---END JQ_NIX_PATHS_OUTPUT---" >&2

  PACKAGE_STORE_PATHS_ARGS=$(echo "$JQ_NIX_PATHS_OUTPUT" | tr '\n' ' ')
fi

# Debug output (commented out by default)
# echo "Debug: PACKAGE_STORE_PATHS_ARGS (after tr '\n' ' '): [$PACKAGE_STORE_PATHS_ARGS]" >&2

if [ -z "$PACKAGE_STORE_PATHS_ARGS" ] || [ -z "${PACKAGE_STORE_PATHS_ARGS// /}" ]; then 
  if [ $NIX_EVAL_EXIT_CODE -eq 0 ]; then # Only print this if nix eval didn't already error
    # This message will go to stderr. The stdout message is handled in the main logic.
    echo "(No valid Nix store paths found in environment.systemPackages of $FULL_FLAKE_REF after jq processing)" >&2 
  fi
  # PROCESSED_NIX_PACKAGES_JSON will remain "[]"
else
  # Inform user about the path-info step
  echo "Fetching Nix package details (this may take a moment for many packages)..." >&2
  if [ -n "${PACKAGE_STORE_PATHS_ARGS// /}" ]; then 
    NIX_PATH_INFO_RAW_OUTPUT=$(nix path-info --json $PACKAGE_STORE_PATHS_ARGS 2>&1)
    NIX_PATH_INFO_EXIT_CODE=$?
    
    # Debug output (commented out by default)
    # echo "Debug: NIX_PATH_INFO_EXIT_CODE: $NIX_PATH_INFO_EXIT_CODE" >&2
    # echo "Debug: NIX_PATH_INFO_RAW_OUTPUT (raw from nix path-info):" >&2
    # echo "$NIX_PATH_INFO_RAW_OUTPUT" >&2 

    if [ $NIX_PATH_INFO_EXIT_CODE -ne 0 ]; then
      echo "Error running 'nix path-info --json ...' for Nix systemPackages:" >&2
      echo "$NIX_PATH_INFO_RAW_OUTPUT" >&2
      # PROCESSED_NIX_PACKAGES_JSON remains "[]"
    else
      PROCESSED_NIX_PACKAGES_JSON=$(echo "$NIX_PATH_INFO_RAW_OUTPUT" | jq '
        [
          to_entries[] | .key as $storepath | .value as $info_obj | 
          ($info_obj.name // ($storepath | split("/") | last | sub("^[a-z0-9]{32}-"; ""))) as $name_version |
          ($info_obj.pname // ($name_version | sub("-([0-9]+|git.+)(\\..+|[a-zA-Z0-9._-]*)*$"; ""))) as $pname_val |
          {
            path: $storepath,
            name: $name_version,
            pname: $pname_val
          }
        ]
      ')
    fi
  else
    # This case should ideally not be reached if the outer check for PACKAGE_STORE_PATHS_ARGS is robust
    PROCESSED_NIX_PACKAGES_JSON="[]" 
  fi
fi

# Debug output (commented out by default)
# echo "Debug: PROCESSED_NIX_PACKAGES_JSON (Nix packages):" >&2
# echo "$PROCESSED_NIX_PACKAGES_JSON" >&2 

# --- Main Logic ---

if [ -z "$PACKAGE_ARG" ]; then # List all Nix packages mode
  NIX_PACKAGE_NAMES=$(echo "$PROCESSED_NIX_PACKAGES_JSON" | jq -r '.[].name // empty' | sort -u)
  
  if [ -z "$NIX_PACKAGE_NAMES" ]; then
    # This condition covers cases where nix eval found nothing, or nix path-info failed,
    # or the final jq processing of path-info data yielded no names.
    echo "(No Nix packages found or could be listed from $FULL_FLAKE_REF)"
  elif [ -n "$NIX_PACKAGE_NAMES" ]; then
    echo "$NIX_PACKAGE_NAMES" 
  fi
  
  # --- List Homebrew Packages (Corrected) ---
  echo "" # Separator
  echo "--- Homebrew Packages ---"
  if command -v brew &> /dev/null; then
    echo "Installed Homebrew Packages (Formulae and Casks):"
    if ! brew list; then # brew list shows both formulae and casks
        echo "(No Homebrew packages installed or error listing them)" >&2
    fi
  else
    echo "Homebrew command ('brew') not found. Skipping Homebrew package listing."
  fi
  exit 0
fi

# Logic for listing files of a specific Nix package
MATCHING_NIX_PACKAGES_JSON=$(echo "$PROCESSED_NIX_PACKAGES_JSON" | jq \
  --arg pkg_arg "$PACKAGE_ARG" \
  '[.[] | select((.name // "") == $pkg_arg or (.pname // "") == $pkg_arg)]')

MATCH_COUNT=$(echo "$MATCHING_NIX_PACKAGES_JSON" | jq 'length')

if [ "$MATCH_COUNT" -eq 0 ]; then
  echo "Error: Nix package '$PACKAGE_ARG' not found among environment.systemPackages for '$DARWIN_CONFIG_NAME'." >&2
  echo "Run '$(basename "$0") $DARWIN_CONFIG_NAME' to see the list of all installed Nix packages (if any)." >&2
  exit 1
elif [ "$MATCH_COUNT" -gt 1 ];then
  echo "Error: Nix package name '$PACKAGE_ARG' is ambiguous and matches multiple packages:" >&2
  echo "$MATCHING_NIX_PACKAGES_JSON" | jq -r '.[].name' | sed 's/^/  /' >&2
  exit 1
fi

STORE_PATH=$(echo "$MATCHING_NIX_PACKAGES_JSON" | jq -r '.[0].path // empty') 
ACTUAL_PACKAGE_NAME=$(echo "$MATCHING_NIX_PACKAGES_JSON" | jq -r '.[0].name // empty')

if [ -z "$STORE_PATH" ] || [ "$STORE_PATH" == "null" ] || [ "$STORE_PATH" == "empty" ]; then
  echo "Internal Error: Could not determine store path for Nix package '$ACTUAL_PACKAGE_NAME'." >&2
  exit 1
fi

if [ ! -e "$STORE_PATH" ]; then 
  echo "Error: Store path '$STORE_PATH' for Nix package '$ACTUAL_PACKAGE_NAME' does not exist." >&2
  exit 1
fi

echo "Files for Nix package $ACTUAL_PACKAGE_NAME (from $STORE_PATH):" 
if ! find "$STORE_PATH" -print; then
  echo "Error: 'find $STORE_PATH -print' encountered an issue." >&2
  exit 1
fi

exit 0
