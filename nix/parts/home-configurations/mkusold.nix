{ self, ... }:
{
  flake.homeConfigurations = {
    "mkusold" = self.lib.mkHome {
      username = "mkusold";
      system = "aarch64-darwin";
    };
  };
}
