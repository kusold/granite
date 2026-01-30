# Override openclaw package to build UI elements
{ inputs, ... }:
{
  flake.overlays.openclaw = (
    final: prev:
    let
      # Get the base openclaw package from llm-agents
      openclaw-base = inputs.llm-agents.legacyPackages.${prev.system}.llm-agents.openclaw or prev.llm-agents.openclaw;
    in
    {
      llm-agents = prev.llm-agents // {
        openclaw = openclaw-base.overrideAttrs (old: {
          buildPhase = old.buildPhase or "" + ''
            runHook preBuild

            # Build the main package
            pnpm build

            # Build the UI
            pnpm ui:build

            runHook postBuild
          '';
        });
      };
    }
  );
}
