{ inputs, ... }: {
  imports = [
    inputs.self.homeModules.mike
    inputs.nix-clawdbot.homeManagerModules.clawdbot
    inputs.self.homeModules.clawdbot
  ];
}
