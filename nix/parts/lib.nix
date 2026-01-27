{ inputs, self, ... }:
{
  flake.lib = {
    # Creates a standalone home-manager configuration with overlays and allowUnfree applied
    mkHome =
      {
        username,
        system,
        homeDirectory ?
          if builtins.match ".*-darwin" system != null then "/Users/${username}" else "/home/${username}",
        extraModules ? [ ],
      }:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ self.overlays.default ];
        };
        extraSpecialArgs = {
          inherit inputs system;
          pkgs-unstable = import inputs.nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };
        };
        modules =
          [
            self.homeModules.${username}
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
            }
          ]
          ++ extraModules;
      };
  };
}
