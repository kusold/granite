# Common home-manager configuration shared across all users
# Exports: flake.modules.homeManager.common
# Note: nix.package is not set here because home-manager's NixOS module
# automatically forwards config.nix.package to each user's home-manager config.
{ ... }:
{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
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
        sqlite
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
      ];
    };
}
