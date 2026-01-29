# Zsh configuration
# Exports: flake.modules.homeManager.zsh
{ ... }:
{
  flake.modules.homeManager.zsh = { lib, ... }: {
    programs.zsh = {
      enable = true;
      initContent = lib.mkBefore ''
        export ZDOTDIR=''${ZDOTDIR:-~/.config/zsh}
        . ''${ZDOTDIR}/.zshenv
        . ''${ZDOTDIR}/.zlogin
        . ''${ZDOTDIR}/.zprofile

        . ''${ZDOTDIR}/.zshrc
      '';
    };
  };
}
