# Dendritic Nix Pattern

## Overview

This flake uses the [Dendritic pattern](https://github.com/mightyiam/dendritic) where:
- Every `.nix` file in `modules/` is a flake-parts module (auto-imported via import-tree)
- Home-manager modules are defined inline within flake-parts modules
- Modules reference each other via `config.flake.modules.homeManager.*` (no file path imports)

## Consumer Usage

**Recommended (type-safe with class checking):**
```nix
home-manager.users.mike = inputs.granite.modules.homeManager.mike-dev;
```

**Also supported (backward compatible):**
```nix
home-manager.users.mike = inputs.granite.homeModules.mike-dev;
```

**Standalone:**
```bash
home-manager switch --flake .#mike
home-manager switch --flake '.#mike@Mac.int.rockymtn.org'
```

## Architecture

```
granite/
├── flake.nix                           # Minimal: inputs + import-tree
├── flake.lock
└── modules/                            # Flake-parts modules (auto-imported)
    ├── systems.nix                     # systems = [...]
    ├── inputs.nix                      # Import flake-parts.flakeModules.modules + home-manager
    ├── formatter.nix                   # perSystem.formatter
    ├── lib.nix                         # flake.lib.mkHome
    ├── overlays/
    │   ├── compose.nix                 # Composes all overlays into default
    │   ├── claude-code.nix
    │   ├── beads.nix
    │   └── nix-clawdbot.nix
    └── home/
        ├── common.nix                  # exports flake.modules.homeManager.common
        ├── git.nix                     # exports flake.modules.homeManager.git
        ├── neovim.nix
        ├── zsh.nix
        ├── clawdbot.nix
        ├── darwin.nix
        ├── mike.nix                    # imports common, git, neovim, zsh
        ├── mike-dev.nix                # imports mike + clawdbot
        ├── mkusold.nix
        ├── modules.nix                 # External modules + homeModules backward compat
        └── configurations.nix          # flake.homeConfigurations.*
```

## Key Patterns

### 1. Minimal flake.nix with import-tree

```nix
outputs = inputs:
  inputs.flake-parts.lib.mkFlake { inherit inputs; }
    (inputs.import-tree ./modules);
```

### 2. Standalone modules (no imports from other home-manager modules)

```nix
# modules/home/git.nix
{ ... }:
{
  flake.modules.homeManager.git = { ... }: {
    programs.gh.enable = true;
    programs.gh-dash.enable = true;
  };
}
```

### 3. Modules that import other modules (dogfooding pattern)

Use `config.flake.modules.homeManager` to reference other modules instead of file paths:

```nix
# modules/home/mike.nix
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.mike = { pkgs, ... }: {
    imports = [
      localModules.common    # Not ./common.nix!
      localModules.git
      localModules.neovim
      localModules.zsh
    ];

    home.stateVersion = "25.11";
    home.packages = [ ... ];
  };
}
```

### 4. Composing user configurations

```nix
# modules/home/mike-dev.nix
{ config, ... }:
let
  localModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.mike-dev = { ... }: {
    imports = [
      localModules.mike
      localModules.clawdbot
    ];
  };
}
```

## Why This Pattern?

1. **True Dendritic** - Every `.nix` file is a flake-parts module (no separate directories)
2. **No file path imports** - Modules reference each other via flake outputs
3. **Type safety** - `flake.modules.homeManager.*` includes `_class = "homeManager"` metadata
4. **Dogfooding** - We use `config.flake.modules.homeManager` to reference our own modules
5. **Composable** - External flakes can import individual modules or compose them
6. **Simple** - One file per module, no wrapper/impl split needed

## Type Safety

The `flake.modules.homeManager.*` exports include `_class = "homeManager"` metadata:
- Importing a home-manager module into a NixOS config will give a clear type error
- Better error messages when modules are used incorrectly

## Flake Outputs

- `modules.homeManager.*` - Type-safe reusable home-manager modules
- `homeModules.*` - Same modules, for backward compatibility  
- `homeConfigurations.*` - Standalone home-manager configurations
- `overlays.default` - Combined overlay with all packages
- `overlays.{beads,claude-code,nix-clawdbot}` - Individual overlays
- `lib.mkHome` - Helper to create standalone home-manager configs

## References

- [Dendritic Pattern](https://github.com/mightyiam/dendritic)
- [import-tree](https://github.com/vic/import-tree)
- [flake.parts: Dogfood a Reusable Module](https://flake.parts/dogfood-a-reusable-module)
- [flake.parts: flake-parts.modules](https://flake.parts/options/flake-parts-modules.html)
