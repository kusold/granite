# Common home-manager configuration shared across all users
# Exports: flake.modules.homeManager.common
{ ... }:
{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      programs.bat.enable = true;

      programs.direnv = {
        enable = true;
        enableZshIntegration = true;
        nix-direnv.enable = true;
      };

      programs.htop.enable = true;
      programs.jq.enable = true;
      programs.ripgrep.enable = true;

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
    };
}
