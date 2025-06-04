#!/usr/bin/env bash
# nix-list.sh: Lists Nix packages from environment.systemPackages in a nix-darwin flake,
#              optionally lists Homebrew packages.

# Immediately exit on errors, undefined variables, or pipe failures
set -euo pipefail

# --- Configuration ---
: "${FLAKE_DIR:="$HOME/.config/nix"}"
# --- End Configuration ---

# Function to show usage
usage() {
  echo "Usage: $(basename "$0") <config-name>"
  echo ""
  echo "Lists all packages installed in your nix-darwin system and Homebrew."
  echo ""
  echo "Arguments:"
  echo "  <config-name>: The name of your darwinConfiguration output"
  echo "                 in your flake.nix (e.g., 'hostname')"
  echo ""
  echo "Example:"
  echo "  $(basename "$0") hostname"
  echo ""
  echo "Flake directory used: $FLAKE_DIR"
  exit 1
}

# Function to list Nix packages from flake
list_nix_packages() {
  local darwin_config="$1"
  local flake_attr="darwinConfigurations.\"$darwin_config\".config.environment.systemPackages"
  local full_flake_ref="$FLAKE_DIR#$flake_attr"

  echo "--- Nix Packages (from current flake definition) ---"

  # Evaluate the flake attribute to get package paths
  local nix_eval_output
  if ! nix_eval_output=$(nix eval --json --no-allow-import-from-derivation --impure "$full_flake_ref" 2>/dev/null); then
    echo "Error evaluating flake attribute $full_flake_ref" >&2
    return 1
  fi

  # Extract and format package names
  local package_names
  if ! package_names=$(echo "$nix_eval_output" | jq -r '
    def clean_name:
      split("/")[-1] |
      sub("^[a-z0-9]{32}-"; "") |
      sub("-[0-9].*$"; "");
    .[] | clean_name
  ' | sort -u); then
    echo "Error processing package names" >&2
    return 1
  fi

  if [ -z "$package_names" ]; then
    echo "(No Nix packages found in $flake_attr)"
  else
    echo "$package_names"
  fi
}

# Function to list Homebrew packages
list_homebrew_packages() {
  echo ""
  echo "--- Homebrew Packages ---"
  if command -v brew &> /dev/null; then
    echo "Installed Homebrew Packages (Formulae and Casks):"
    if ! brew list; then
      echo "(No Homebrew packages installed or error listing them)"
    fi
  else
    echo "(Homebrew not installed)"
  fi
}

# --- Main ---
if [ $# -ne 1 ]; then
  echo "Error: Missing config-name argument." >&2
  usage
fi

DARWIN_CONFIG_NAME="$1"

# List packages from both package managers
list_nix_packages "$DARWIN_CONFIG_NAME"
list_homebrew_packages
