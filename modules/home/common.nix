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

      home.packages = with pkgs; [
        awscli2
        btop
		fzf
        gh
        git
        go
        home-manager
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
