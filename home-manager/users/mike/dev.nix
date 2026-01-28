{ inputs, ... }: {
  imports = [
    ./mike.nix
    inputs.nix-clawdbot.homeManagerModules.clawdbot
    ../../_modules/clawdbot.nix
  ];
}
