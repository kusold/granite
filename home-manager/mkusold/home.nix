{
  config,
  lib,
  pkgs,
  #  pkgs-unstable,
  #  gui,
  #  darwin,
  inputs,
  ...
} @ args: {
  imports = [
    ../_modules/git.nix
    ../_modules/neovim.nix
    ../_modules/zsh.nix
    #    ]
    #    ++ lib.optionals darwin [
    #      (import ../_modules/darwin.nix args)
  ];

  home.stateVersion = "23.11";

  home.packages = [
    pkgs.aws-sam-cli
    pkgs.awscli2
    pkgs.bat
    pkgs.docker-compose
    pkgs.gh
    pkgs.gnupg
    pkgs.htop
    pkgs.jdk22
    pkgs.jq
    pkgs.k9s
    pkgs.kubernetes-helm
    pkgs.mas
    pkgs.ponysay
    pkgs.restic
    pkgs.ripgrep
    pkgs.shellcheck
    pkgs.sqlite
    pkgs.ssh-copy-id
    pkgs.tree
    pkgs.unar
    pkgs.wget
    pkgs.yq
    pkgs.yt-dlp

    # Added while trying to get neovim working well
    pkgs.gnumake
    pkgs.gcc
    pkgs.nodejs_20
    pkgs.unzip
    pkgs.go
    #    ]
    #    ++ lib.optionals gui [
    #      pkgs-unstable.jetbrains.idea-ultimate
    #      pkgs-unstable.vscode
  ];
  programs.home-manager.enable = true;

  #  programs.kitty = {
  #    enable =
  #      if gui
  #      then true
  #      else false; # Yes, this could just be gui, but I'm still playing with how I want to structure this.
  #    darwinLaunchOptions = [
  #      "--single-instance"
  #    ];
  #    font.name = "FiraCode Nerd Font";
  #    font.size = 11;
  #    theme = "Dark One Nuanced";
  #    settings = {
  #      update_check_interval = 0;
  #      tab_bar_edge = "top";
  #      tab_bar_style = "powerline";
  #      macos_quit_when_last_window_closed = true;
  #      confirm_os_window_close = 0;
  #    };
  #  };

  home.file."./bin/" = {
    source = ../../bin;
    recursive = true;
  };
}
