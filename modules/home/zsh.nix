# Zsh configuration
# Exports: flake.modules.homeManager.zsh
{ ... }:
{
  flake.modules.homeManager.zsh =
    { lib, ... }:
    {
      programs.zsh = {
        enable = true;
        completionInit = "";      # compinit handled by belak/zsh-utils in custom .zshrc
        shellAliases = {};        # aliases handled in custom .zshrc
        initContent = lib.mkMerge [
          (lib.mkBefore ''
            export ZDOTDIR=''${ZDOTDIR:-~/.config/zsh}
            . ''${ZDOTDIR}/.zshenv
          '')
          (lib.mkAfter ''
            . ''${ZDOTDIR}/.zshrc
          '')
        ];
      };
    };
}
