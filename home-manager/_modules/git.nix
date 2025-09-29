{
  ...
}@args:
{
  programs.git = {
    enable = true;
    includes = [ { path = "~/.config/home-manager/config/git/config"; } ];
  };

  programs.gh = {
    enable = true;
  };
  programs.gh-dash = {
    enable = true;
  };
}
