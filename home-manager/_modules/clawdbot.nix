# Clawdbot AI Agent Configuration
{ config, lib, pkgs, ... }:
{
  programs.clawdbot = {
    enable = true;
    # Set documents to null to skip the file existence checks
    # You can configure AGENTS.md, SOUL.md, and TOOLS.md manually later
    documents = null;
    instances.default = {
      enable = true;
    };
  };
}
