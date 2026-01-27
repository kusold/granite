# Home-Manager Modules

This directory contains home-manager configurations that can be used in two ways:

## 1. Standalone (via `home-manager switch`)

```bash
home-manager switch --flake .#mike@dev
```

## 2. From NixOS

In your NixOS configuration (`/etc/nixos/configuration.nix` or flake):

```nix
{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    granite.url = "path:/home/mike/Development/granite";
  };

  outputs = { self, nixpkgs, home-manager, granite, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          # Import the appropriate home module for the user
          home-manager.users.mike = granite.homeModules.mike-dev;
        }
      ];
    };
  };
}
```

## Available Modules

| Module | Description |
|--------|-------------|
| `mike` | Base mike configuration |
| `mike-dev` | Mike's config + clawdbot (for dev host) |
| `mkusold` | Mkusold's configuration |
| `common` | Shared base configuration |
| `git` | Git/GitHub configuration |
| `neovim` | Neovim configuration |
| `zsh` | Zsh configuration |
| `clawdbot` | Clawdbot AI agent configuration |
