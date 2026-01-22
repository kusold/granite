{
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}@args:
{
  imports = [
    ../_modules/common.nix
    ../_modules/git.nix
    ../_modules/neovim.nix
    ../_modules/zsh.nix
    # ]
    # ++ lib.optionals darwin [
    #   (import ../_modules/darwin.nix args)
  ];
  home.stateVersion = "25.11";
  # NOTE: nixpkgs.config and nixpkgs.overlays are NOT set here.
  # When used with useGlobalPkgs = true (e.g., rockymtn), they are ignored.
  # For standalone use, the homeConfiguration in flake.nix applies them.

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
      beads-with-completions
    ])
    # Packages from unstable channel
    ++ (with pkgs-unstable; [
      opencode # fast-moving project, want bleeding edge
      yt-dlp # needs frequent updates for site compatibility
    ]);

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
