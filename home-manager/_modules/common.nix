{
  pkgs,
  inputs,
  ...
}: {
  programs.bat = {
    enable = true;
  };
  programs.direnv = {
    enable = true;
    enableZshIntegration = true; # see note on other shells below
    nix-direnv.enable = true;
  };

  programs.htop = {
    enable = true;
  };

  programs.jq = {
    enable = true;
  };
  programs.ripgrep = {
    enable = true;
  };
  programs.tmux = {
    enable = true;
  };

  home.packages = with pkgs; [
    alejandra
    ssh-copy-id
    tree
    unar
    unzip
    wget
    yadm
    yq
  ];
}
