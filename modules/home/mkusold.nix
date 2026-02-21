# Mkusold's home-manager configuration
# Exports: flake.modules.homeManager.mkusold
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.mkusold =
    { pkgs, pkgs-unstable, ... }:
    {
      imports = [
        localModules.common
        localModules.git
        localModules.neovim
        localModules.yadm
        localModules.zsh
      ];

      home.stateVersion = "25.11";

      home.packages = [
			  pkgs.sonar-scanner-cli
        # unstable isn't needed, but stable has build failures
        pkgs-unstable.aws-sam-cli
        pkgs.docker-compose
        pkgs.gnupg
        pkgs.jdk25
        pkgs.mas
        pkgs.maven

        # Added while trying to get neovim working well
        pkgs.gnumake
        pkgs.gcc
        pkgs.nodejs

        # AI
        pkgs.dolt
      ];

      programs.home-manager.enable = true;

      home.file."./bin/" = {
        source = ../../bin;
        recursive = true;
      };
    };
}
