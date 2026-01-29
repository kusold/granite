# Neovim configuration
# Exports: flake.modules.homeManager.neovim
{ ... }:
{
  flake.modules.homeManager.neovim =
    { pkgs, ... }:
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
        vimdiffAlias = true;
      };

      home.packages = with pkgs; [
        # Needed for various plugins to compile
        gcc
        gnumake
        go
        unzip
      ];
    };
}
