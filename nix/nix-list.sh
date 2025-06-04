#!/usr/bin/env bash
# nix-list.sh: Lists Nix packages from environment.systemPackages in a nix-darwin flake,
#              optionally lists Homebrew packages, and shows what was updated in the last rebuild.

# Immediately exit on errors, undefined variables, or pipe failures
set -euo pipefail

# --- Configuration ---
: "${FLAKE_DIR:="$HOME/.config/nix"}"
# --- End Configuration ---

# Function to show usage
usage() {
  echo "Usage: $(basename "$0") <config-name> [--updated]"
  echo ""
  echo "Lists all packages installed in your nix-darwin system and Homebrew."
  echo ""
  echo "Arguments:"
  echo "  <config-name>: The name of your darwinConfiguration output"
  echo "                 in your flake.nix (e.g., 'hostname')"
  echo "Options:"
  echo "  --updated: Show what changed in the last rebuild"
  echo ""
  echo "Example:"
  echo "  $(basename "$0") hostname"
  echo "  $(basename "$0") hostname --updated"
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

# Function to show what was updated in the last rebuild
show_updates() {
  echo ""
  echo "--- Recent Updates ---"
  
  # Get the current generation number
  local current_gen
  if ! current_gen=$(darwin-rebuild --list-generations 2>/dev/null | tail -n1 | awk '{print $1}'); then
    echo "Error: Could not determine current generation"
    return 1
  fi
  
  if [ -z "$current_gen" ] || [ "$current_gen" -eq 0 ]; then
    echo "No previous generations found"
    return
  fi
  
  local prev_gen=$((current_gen - 1))
  
  # Get timestamps for the generations
  local prev_time current_time
  prev_time=$(stat -f "%c" "/nix/var/nix/profiles/system-${prev_gen}-link" 2>/dev/null | xargs -I{} date -r {} "+%b %d %H:%M:%S %Y")
  current_time=$(stat -f "%c" "/nix/var/nix/profiles/system" 2>/dev/null | xargs -I{} date -r {} "+%b %d %H:%M:%S %Y")
  
  echo "Comparing generations:"
  echo "  $prev_gen (${prev_time:-unknown time})"
  echo "→ $current_gen (${current_time:-unknown time})"
  echo ""
  
  # Get the derivation paths for both generations
  local prev_path="/nix/var/nix/profiles/system-${prev_gen}-link"
  local current_path="/nix/var/nix/profiles/system"
  
  local prev_drv current_drv
  if ! prev_drv=$(readlink -f "$prev_path"); then
    echo "Error: Could not resolve previous generation path: $prev_path"
    return 1
  fi
  
  if ! current_drv=$(readlink -f "$current_path"); then
    echo "Error: Could not resolve current generation path: $current_path"
    return 1
  fi
  
  # Extract versions for display
  local prev_ver current_ver
  prev_ver=$(basename "$prev_drv" | sed -E 's/.*darwin-system-//; s/-.*$//')
  current_ver=$(basename "$current_drv" | sed -E 's/.*darwin-system-//; s/-.*$//')

  # Compare the two derivations
  local changes
  if ! changes=$(nix store diff-closures "$prev_drv" "$current_drv" 2>/dev/null); then
    echo "Error comparing generations."
    return 1
  fi

  # Show system version change if it occurred
  if [ "$prev_ver" != "$current_ver" ]; then
    echo "System version: $prev_ver → $current_ver"
  fi

  # Process changes to show actual package updates
  local changes_found=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^[→←⊕⊖] ]] && [[ ! "$line" =~ "darwin-system" ]]; then
      if ! $changes_found; then
        echo ""
        echo "Package changes:"
        changes_found=true
      fi
      echo "  $line"
    fi
  done <<< "$changes"

  if ! $changes_found; then
    echo ""
    echo "No package changes detected"
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

# Function to show Homebrew package changes
show_homebrew_changes() {
  if ! command -v brew &> /dev/null; then
    return 0
  fi

  local changes_found=false
  echo ""
  echo "--- Recent Homebrew Changes ---"

  # Check for recently installed formulae
  local installed
  if installed=$(find "$(brew --prefix)/Cellar" -type d -mtime -1 -mindepth 1 -maxdepth 1 2>/dev/null); then
    if [ -n "$installed" ]; then
      changes_found=true
      echo "Updated formulae:"
      echo "$installed" | while IFS= read -r formula; do
        name=$(basename "$formula")
        version=$(ls -t "$formula" | head -n1)
        echo "  $name ($version)"
      done
      echo ""
    fi
  fi

  # Check for recently installed casks
  local casks
  if casks=$(find "$(brew --prefix)/Caskroom" -type d -mtime -1 -mindepth 1 -maxdepth 1 2>/dev/null); then
    if [ -n "$casks" ]; then
      changes_found=true
      echo "Updated casks:"
      echo "$casks" | while IFS= read -r cask; do
        name=$(basename "$cask")
        version=$(ls -t "$cask" | head -n1)
        echo "  $name ($version)"
      done
      echo ""
    fi
  fi

  if ! $changes_found; then
    echo "  No recent changes"
  fi
}

# --- Main ---
SHOW_UPDATES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --updated)
      SHOW_UPDATES=true
      shift
      ;;
    *)
      DARWIN_CONFIG_NAME="$1"
      shift
      ;;
  esac
done

if [ -z "${DARWIN_CONFIG_NAME:-}" ]; then
  echo "Error: Missing config-name argument." >&2
  usage
fi

# Show either updates or current package list
if [ "$SHOW_UPDATES" = "true" ]; then
  show_updates
  show_homebrew_changes
else
  list_nix_packages "$DARWIN_CONFIG_NAME"
  list_homebrew_packages
fi
