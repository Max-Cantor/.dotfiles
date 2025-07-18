{
  description = "Max Invisible Technologies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew, homebrew-core, homebrew-cask, ... }:
  let
    configuration = { pkgs, config, ... }: {

      nixpkgs.config.allowUnfree = true;

      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [
          pkgs.act
          pkgs.arc-browser
          pkgs.argocd
          pkgs.code-cursor
          # Commenting out due to unresolved compatibility issues with python 3.13.
          # pkgs.datadog-agent
          pkgs.gnumake
          pkgs.go
          pkgs.google-chrome
          pkgs.google-cloud-sdk
          pkgs.iterm2
          pkgs.jq
          pkgs.kubectl
          pkgs.kubernetes-helm
          pkgs.libpq
          pkgs.metabase
          pkgs.mkalias
          pkgs.neovim
          pkgs.newman
          pkgs.nix-diff
          pkgs.poetry
          pkgs.postgresql
          pkgs.postman
          pkgs.pre-commit
          pkgs.python314
          pkgs.python312
          pkgs.redis
          pkgs.terraform
          pkgs.uv
          pkgs.vim
          pkgs.vscode
          pkgs.warp-terminal
        ];

      homebrew = {
        enable = true;
        taps = [];
        brews = [
          "node"
          "pipx"
          "python@3.9"
          "rust"
          "tox"
          "vercel-cli"
        ];
        casks = [
          "clickup"
          "datadog-agent"
          "docker-desktop"
          "github"
          "notion"
          "sublime-text"
          "zen"
        ];
        onActivation.cleanup = "zap";
        onActivation.autoUpdate = true;
        onActivation.upgrade = true;
      };
      # Activation Script
      # Mac aliasing so Applications recognizes nix installed packages.
      system.activationScripts.applications.text = let
        env = pkgs.buildEnv {
          name = "system-applications";
          paths = config.environment.systemPackages;
          pathsToLink = "/Applications";
        };
      in
        pkgs.lib.mkForce ''
        # Set up applications.
        echo "setting up /Applications..." >&2
        rm -rf /Applications/Nix\ Apps
        mkdir -p /Applications/Nix\ Apps
        find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
        while read -r src; do
          app_name=$(basename "$src")
          echo "copying $src" >&2
          ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
        done
            '';

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # Set primary user for options that require it (like homebrew)
      system.primaryUser = "max";

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#simple
    darwinConfigurations."maxIT" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;

            # Apple Silicon Only: Also install Homebrew under the default INtel prefix for Rosetta 2
            enableRosetta = true;

            # User owning the Homebrew prefix
            user = "max";

            # Automatically migrate existing Homebrew installations
            autoMigrate = true;
          };
        }
      ];
    };
  };
}
