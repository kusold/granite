# Mike's base home-manager configuration
# Exports: flake.modules.homeManager.mike
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.mike = { pkgs, pkgs-unstable, ... }: {
    imports = [
      localModules.common
      localModules.git
      localModules.neovim
      localModules.zsh
    ];

    home.stateVersion = "25.11";

    home.packages =
      (with pkgs; [
        age # encryption tool
        ansible
        aspell
        awscli2 # AWS CLI v2
        bat # better cat
        bfg-repo-cleaner
        exiftool
        fdupes
        gh
        git
        git-filter-repo
        gitleaks
        go-migrate
        go-task
        goose-cli
        htop
        jq
        k3sup
        k9s
        kompose
        kubernetes-helm
        kustomize
        mosh
        nixd # Nix LSP
        nixpkgs-fmt
        opentofu
        ponysay
        pre-commit
        restic
        resticprofile
        ripgrep
        rsync
        shellcheck
        sops
        sqlite
        ssh-copy-id
        tmux
        tree
        unar
        vim
        wakeonlan
        wget
        yadm

        go # language:go
        ruby # language:ruby
        nodejs_24 # language:javascript
        python3 # language:python
        poetry # language:python
        uv # language:python
        cargo # language:rust
        rustc # language:rust

        # From Overlays
        claude-code
        beads
      ])
      # Packages from unstable channel
      ++ (with pkgs-unstable; [
        opencode # fast-moving project, want bleeding edge
        yt-dlp # needs frequent updates for site compatibility
      ]);

    programs.home-manager.enable = true;
  };
}
