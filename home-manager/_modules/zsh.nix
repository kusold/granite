{
  config,
  lib,
  pkgs,
  gui,
  darwin,
  ...
}@args:
{
  programs.zsh = {
    enable = true;
    # dotDir doesn't allow me to manage that directory myself
    #dotDir = ".config/zsh";
    initContent = lib.mkBefore ''
      export ZDOTDIR=''${ZDOTDIR:-~/.config/zsh}
      . ''${ZDOTDIR}/.zshenv
      . ''${ZDOTDIR}/.zlogin
      . ''${ZDOTDIR}/.zprofile

      . ''${ZDOTDIR}/.zshrc
    '';
  };
  #home.packages = with pkgs; [ zsh ];
}
