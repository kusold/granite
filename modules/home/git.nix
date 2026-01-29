# Git/GitHub tools configuration
# Exports: flake.modules.homeManager.git
{ ... }:
{
  flake.modules.homeManager.git =
    { ... }:
    {
      programs.gh.enable = true;
      programs.gh-dash.enable = true;
    };
}
