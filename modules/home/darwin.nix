# Darwin-specific home-manager configuration
# Exports: flake.modules.homeManager.darwin
{ ... }:
{
  flake.modules.homeManager.darwin =
    { ... }:
    {
      # Hammerspoon is a macOS automation tool
      home.file."./.config/hammerspoon/" = {
        source = ../../config/hammerspoon;
        recursive = true;
      };
    };
}
