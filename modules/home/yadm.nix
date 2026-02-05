# YADM dotfiles integration
# Clones/pulls dotfiles on every home-manager switch
{ ... }:
{
  flake.modules.homeManager.yadm = { lib, pkgs, ... }: {
    home.activation.yadmSync = lib.hm.dag.entryAfter ["writeBoundary"] ''
      YADM="${pkgs.yadm}/bin/yadm"
      REPO="https://github.com/kusold/dotfiles"

      # Check if YADM repo is already cloned
      if ! $YADM status &>/dev/null; then
        echo "YADM: Cloning dotfiles from $REPO..."
        $DRY_RUN_CMD $YADM clone --no-bootstrap "$REPO" || {
          echo "YADM: Warning - clone failed" >&2
        }
      else
        echo "YADM: Pulling latest dotfiles..."
        $DRY_RUN_CMD $YADM pull || {
          echo "YADM: Warning - pull failed (maybe offline?)" >&2
        }
      fi
    '';
  };
}
