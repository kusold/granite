{ self, ... }:
{
  flake.homeConfigurations = {
    # Hostname-based for automatic detection
    "mike@Mac.int.rockymtn.org" = self.lib.mkHome {
      username = "mike";
      system = "aarch64-darwin";
      homeModule = self.homeModules.mike;
    };

    "mike@dev" = self.lib.mkHome {
      username = "mike";
      system = "x86_64-linux";
      homeModule = self.homeModules.mike-dev;
      extraModules = [ self.homeModules.clawdbot-external ];
    };

    # Fallback configuration (when hostname doesn't match)
    "mike" = self.lib.mkHome {
      username = "mike";
      system = "x86_64-linux";
      homeModule = self.homeModules.mike;
    };
  };
}
