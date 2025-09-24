{
  config,
  lib,
  pkgs,
  gui,
  darwin,
  inputs,
  ...
} @ args: {
  programs.zsh = {
    enable = true;
    # dotDir doesn't allow me to manage that directory myself
    #dotDir = ".config/zsh";
    initContent = lib.mkBefore ''
      export ZDOTDIR=~/.config/zsh
      . $ZDOTDIR/.zshenv
      . $ZDOTDIR/.zlogin
      . $ZDOTDIR/.zprofile

      . $ZDOTDIR/.zshrc
    '';
  };
  home.file."./.config/zsh/" = {
    source = ../../config/zsh;
    recursive = true;
  };
}
