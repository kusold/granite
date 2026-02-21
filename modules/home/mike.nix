# Mike's base home-manager configuration
# Exports: flake.modules.homeManager.mike
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.mike =
    { pkgs, pkgs-unstable, ... }:
    {
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
          bfg-repo-cleaner
          exiftool
          fdupes
          git-filter-repo
          gitleaks
          go-migrate
          go-task
          goose-cli
          k3sup
          kompose
          kustomize
          mosh
          pre-commit
          resticprofile
          sops
          wakeonlan

          ruby # language:ruby
          nodejs_24 # language:javascript
          python3 # language:python
          poetry # language:python
          uv # language:python
          cargo # language:rust
          rustc # language:rust

          # From Overlays
          llm-agents.ccusage
          llm-agents.happy-coder
          llm-agents.opencode
        ])
        # Packages from unstable channel
        ++ (with pkgs-unstable; [
          yt-dlp # needs frequent updates for site compatibility
        ]);

      programs.home-manager.enable = true;
    };
}
