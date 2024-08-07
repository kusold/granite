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
    ../_modules/common.nix
    ../_modules/git.nix
    ../_modules/neovim.nix
    ../_modules/zsh.nix
    # ]
    # ++ lib.optionals darwin [
    #   (import ../_modules/darwin.nix args)
  ];
  home.stateVersion = "24.05";
  # nixpkgs.config.allowUnfree = true;
  # nixpkgs.config.allowUnfreePredicate = _: true;

  home.packages = [
    pkgs.ansible
    pkgs.aspell
    pkgs.awscli2
    pkgs.bfg-repo-cleaner
    pkgs.gitleaks
    pkgs.go-migrate
    pkgs.go-task
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
    pkgs.shellcheck
    pkgs.sops
    pkgs.sqlite
    pkgs.opentofu
    pkgs.unar

    # pkgs-unstable.yt-dlp
    pkgs.yt-dlp
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
