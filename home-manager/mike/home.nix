{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  gui,
  darwin,
  inputs,
  ...
} @ args: {
  imports = [
    ../_modules/git.nix
    ../_modules/neovim.nix
    ../_modules/zsh.nix
    # ]
    # ++ lib.optionals darwin [
    #   (import ../_modules/darwin.nix args)
  ];
  home.stateVersion = "23.11";
  # nixpkgs.config.allowUnfree = true;
  # nixpkgs.config.allowUnfreePredicate = _: true;

  programs = {
    direnv = {
      enable = true;
      enableZshIntegration = true; # see note on other shells below
      nix-direnv.enable = true;
    };
  };

  home.packages = [
    pkgs.alejandra
    pkgs.ansible
    pkgs.aspell
    pkgs.awscli2
    pkgs.bat
    pkgs.bfg-repo-cleaner
    pkgs.gh
    pkgs.gitleaks
    pkgs.go-migrate
    pkgs.go-task
    pkgs.htop
    pkgs.jq
    pkgs.k3sup
    pkgs.k9s
    pkgs.kompose
    pkgs.kubernetes-helm
    pkgs.kustomize
    pkgs.mosh
    pkgs.nixpkgs-fmt
    pkgs.nodejs_20
    pkgs.ponysay
    pkgs.pre-commit
    pkgs.restic
    pkgs.cargo # language:rust
    pkgs.rustc # language:rust
    #pkgs.resticprofile
    pkgs.ripgrep
    pkgs.shellcheck
    pkgs.sops
    pkgs.sqlite
    pkgs.ssh-copy-id
    pkgs.ssh-copy-id
    pkgs.opentofu
    pkgs.tmux
    pkgs.tree
    pkgs.unar
    pkgs.wget
    pkgs.yadm

    # pkgs-unstable.yt-dlp
    pkgs.yt-dlp

    # Added while trying to get neovim working well
    # pkgs.gnumake
    # pkgs.gcc
    # pkgs.nodejs_20
    # pkgs.unzip
    # pkgs.go
    # ]
    # ++ lib.optionals gui [
    # pkgs-unstable.jetbrains.idea-ultimate
    # pkgs-unstable.vscode
  ];
  programs.home-manager.enable = true;

  # programs.kitty = {
  #   enable = if gui then true else false; # Yes, this could just be gui, but I'm still playing with how I want to structure this.
  #   darwinLaunchOptions = [
  #     "--single-instance"
  #   ];
  #   font.name = "FiraCode Nerd Font";
  #   font.size = 11;
  #   theme = "Dark One Nuanced";
  #   settings = {
  #     update_check_interval = 0;
  #     tab_bar_edge = "top";
  #     tab_bar_style = "powerline";
  #     macos_quit_when_last_window_closed = true;
  #     confirm_os_window_close = 0;
  #   };
  # };

  home.file."./bin/" = {
    source = ../../bin;
    recursive = true;
  };
}