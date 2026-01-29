# Defines standalone home-manager configurations (homeConfigurations)
# These are evaluated configurations for use with `home-manager switch --flake`
{ self, inputs, ... }:
{
  flake.homeConfigurations = {
    # Hostname-based for automatic detection
    "mike@Mac.int.rockymtn.org" = self.lib.mkHome {
      username = "mike";
      system = "aarch64-darwin";
      homeModule = self.modules.homeManager.mike;
    };

    "mike@dev" = self.lib.mkHome {
      username = "mike";
      system = "x86_64-linux";
      homeModule = self.modules.homeManager.mike-dev;
      # extraModules = [ self.modules.homeManager.clawdbot-external ];
    };

    # Fallback configuration (when hostname doesn't match)
    "mike" = self.lib.mkHome {
      username = "mike";
      system = "x86_64-linux";
      homeModule = self.modules.homeManager.mike;
    };

    "mkusold" = self.lib.mkHome {
      username = "mkusold";
      system = "aarch64-darwin";
      homeModule = self.modules.homeManager.mkusold;
    };
  };
}
