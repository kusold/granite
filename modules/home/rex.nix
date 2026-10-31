# Rex terminal multiplexer (https://www.superlogical.com/rex)
# Exports: flake.modules.homeManager.rex
{ inputs, ... }:
{
  flake.modules.homeManager.rex =
    { ... }:
    {
      imports = [ inputs.rex.homeManagerModules.default ];

      # Personal rex server as a systemd user service, using the same socket
      # as every rex command. Implies programs.rex.enable, which installs the
      # rex CLI and the xterm-rex terminfo entry in ~/.terminfo. Linux only.
      # On dev, rockymtn sets users.users.mike.linger = true, so the server
      # keeps running while mike is logged out.
      services.rex.enable = true;

      # ~/.ssh/config is yadm-managed (dotfiles' .ssh/config##template), so
      # home-manager must not write it (programs.ssh stays off). The guard
      # reaches ssh through the template's top line instead:
      #   Include ~/.config/rex/ssh_config
      # written by `rex terminfo setup` after the first switch. It must sit
      # before the first Host block — the guard is a Match block, and ssh
      # keeps the first value it sees for each setting.
      programs.rex.sshGuard = false;
    };
}
