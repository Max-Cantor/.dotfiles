# Dotfiles

Personal configuration files and tools for system setup and management.

## Directory Structure

- `nix/` - Nix and nix-darwin configuration
  - Package management
  - System configuration
  - Custom tools

## Nix Configuration

### Package Management

```bash
# Update nix flake inputs (e.g., get latest nixpkgs)
nix flake update --flake ~/.config/nix/

# Rebuild and activate system configuration
sudo darwin-rebuild switch --flake ~/.config/nix#<config-name>

# Backup/sync configuration to dotfiles repo
cp -r ~/.config/nix/ ~/.dotfiles/nix/<config-name>
```

### Tools

#### nix-list

A utility script for nix-darwin systems that shows:
- Currently installed Nix packages from flake configuration
- Installed Homebrew packages (if Homebrew is present)
- Changes from last system rebuild (requires sudo)

##### Usage

```bash
# List all currently installed packages
./nix/nix-list.sh <config-name>

# Show updates after last rebuild
sudo ./nix/nix-list.sh <config-name> --updated
```

Where `<config-name>` is the name of your darwinConfiguration in your flake.nix (e.g., "host").

##### Requirements

- nix-darwin system
- Basic Unix tools (bash, sed, jq)
- Sudo access (for viewing system changes)
- Optional: Homebrew (for listing brew packages) 

## Credits

- Nix configuration inspired by [Minimal Nix Darwin Config](https://youtu.be/Z8BL8mdzWHI)
