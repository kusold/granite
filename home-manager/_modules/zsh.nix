{
  config,
  lib,
  pkgs,
  gui,
  darwin,
  inputs,
  ...
}@args:
{
  programs.zsh = {
    enable = true;
    # dotDir doesn't allow me to manage that directory myself
    #dotDir = ".config/zsh";
  };
}
