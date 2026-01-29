# Mkusold's home-manager configuration
# Exports: flake.modules.homeManager.mkusold
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.mkusold = { pkgs, pkgs-unstable, ... }: {
    imports = [
      localModules.common
      localModules.git
      localModules.neovim
      localModules.zsh
    ];

    home.stateVersion = "25.11";

    home.packages = [
      # unstable isn't needed, but stable has build failures
      pkgs-unstable.aws-sam-cli
      pkgs.awscli2
      pkgs.bat
      pkgs.direnv
      pkgs.docker-compose
      pkgs.gnupg
      pkgs.jdk25
      pkgs.jq
      pkgs.k9s
      pkgs.kubernetes-helm
      pkgs.mas
      pkgs.maven
      pkgs.opentofu
      pkgs.ponysay
      pkgs.restic
      pkgs.shellcheck
      pkgs.sqlite
      pkgs.yq

      # Added while trying to get neovim working well
      pkgs.gnumake
      pkgs.gcc
      pkgs.nodejs
      pkgs.unzip
      pkgs.go

      # AI
      pkgs.beads
      pkgs.dolt
    ];

    programs.home-manager.enable = true;

    home.file."./bin/" = {
      source = ../../bin;
      recursive = true;
    };
  };
}
