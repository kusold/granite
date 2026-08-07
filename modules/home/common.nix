# Common home-manager configuration shared across all users
# Exports: flake.modules.homeManager.common
# Note: nix.package uses mkDefault so NixOS module can override it
{ ... }:
{
  flake.modules.homeManager.common =
    { lib, pkgs, ... }:
    {
      # mkDefault (priority 1000) works in every context:
      #  - standalone `home-manager switch`: provides pkgs.nix so the
      #    "nix.package required to generate nix.conf" assertion is satisfied
      #    (the option's own default is null at priority 1500, so this wins).
      #  - imported via the home-manager NixOS/Darwin module: the OS-forwarded
      #    nix.package (priority 100) overrides this, so there is no collision.
      # Do NOT use mkOverride 1500 — that ties home-manager's null default
      # (also 1500) and triggers "defined both null and not null".
      nix.package = lib.mkDefault pkgs.nix;

      # Installs the home-manager CLI from the pinned flake input. Do NOT also add
      # pkgs.home-manager to home.packages — that is a separate build tracking
      # nixpkgs independently, so the two collide on bin/home-manager and can skew
      # the CLI out of sync with the modules evaluating this config.
      # No-op when imported as a NixOS/Darwin submodule (upstream gates it on
      # !submoduleSupport.enable), so this is safe for external consumers.
      # mkDefault so they can opt out with `= false` instead of mkForce.
      programs.home-manager.enable = lib.mkDefault true;

      nix.settings = {
        extra-substituters = [ "https://cache.numtide.com" ];
        extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
      };

      programs.bat.enable = true;

      programs.direnv = {
        enable = true;
        enableZshIntegration = false;
        nix-direnv.enable = true;
      };

      programs.htop.enable = true;
      programs.jq.enable = true;
      programs.ripgrep.enable = true;

      # Shell integrations stay off (their default): they auto-start/auto-attach
      # a session on every shell launch, same reason direnv's is off above.
      programs.zellij.enable = true;

      home.packages = with pkgs; [
        awscli2
        btop
        devenv # devenv.sh; paired with programs.direnv above via `use devenv`
		fzf
        gh
        git
        go
        k9s
        kubernetes-helm
        nixd # Nix LSP
        nixpkgs-fmt
        opentofu
        ponysay
        restic
        rsync
        shellcheck
        sqlite-interactive
        ssh-copy-id
        tmux
        tree
        unar
        unzip
        vim
        wget
        yadm
        yq

        # AI
        llm-agents.beads
        llm-agents.ccstatusline
        llm-agents.ccusage
        llm-agents.openspec
        llm-agents.qmd # mini cli search engine for markdown
      ];
    };
}
