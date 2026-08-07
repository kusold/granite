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

      # gh is enabled in the shared git module; the host config is user-specific.
      programs.gh.hosts = {
        "github.marqeta.com" = {
          git_protocol = "ssh";
          users.mkusold = null;
          user = "mkusold";
        };
      };

      home.file."./bin/" = {
        source = ../../bin;
        recursive = true;
      };
    };
}
