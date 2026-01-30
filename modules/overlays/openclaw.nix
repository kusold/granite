# TODO: UI build requires full source tree which is not included in the llm-agents package
# This overlay is disabled until we can build openclaw from source with all dependencies
# See: https://github.com/numtide/llm-agents.nix/issues

{ inputs, ... }:
{
  # flake.overlays.openclaw = (
  #   final: prev:
  #   let
  #     openclaw-base = inputs.llm-agents.legacyPackages.${prev.system}.llm-agents.openclaw or prev.llm-agents.openclaw;
  #   in
  #   {
  #     llm-agents = prev.llm-agents // {
  #       openclaw = openclaw-base.overrideAttrs (old: {
  #         postInstall = old.postInstall or "" + ''
  #           echo "Building openclaw UI..."
  #           cd $out/lib/openclaw
  #           pnpm ui:build
  #         '';
  #       });
  #     };
  #   }
  # );
}
