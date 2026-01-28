{ inputs, ... }: {
  imports = [
    ./default.nix
    inputs.nix-clawdbot.homeManagerModules.clawdbot
    ../../_modules/clawdbot.nix
  ];
}
