{
  pkgs,
  ...
}:
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
    # nodejs
    unzip
  ];

  #home.file."./.config/nvim/lazy-lock.json" = {
  # source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/nvim/lazy-lock.rw.json";
  # recursive = false;
  #};
}
