# Neovim configuration
# Exports: flake.modules.homeManager.neovim
{ ... }:
{
  flake.modules.homeManager.neovim =
    { lib, pkgs, ... }:
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
        vimdiffAlias = true;
        # No plugin here is a remote plugin, so neither host is ever called.
        # Ruby in particular dragged ~800MiB into the closure.
        withRuby = false;
        withPython3 = false;
      };

      # Let YADM manage init.lua instead of home-manager. The neovim module
      # writes ~/.config/nvim/init.lua whenever it generates Lua config; disabling
      # just this file leaves the path free for YADM to own.
      xdg.configFile."nvim/init.lua".enable = lib.mkForce false;

      home.packages = with pkgs; [
        # Needed for various plugins to compile
        gcc
        gnumake
        go
        # nvim-treesitter `main` branch builds parsers via the tree-sitter CLI
        tree-sitter
        unzip
      ];
    };
}
