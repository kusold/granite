{ inputs, ... }:

{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          prek
          nixfmt
        ];

        shellHook = ''
          echo "Granite Dev Environment"
          echo "======================"
          echo "Available tools:"
          echo "  - prek: pre-commit framework (run 'prek')"
          echo "  - nixfmt: Nix formatter (run 'nixfmt file.nix')"
          echo ""
          echo "Run 'prek run' to run pre-commit checks"
          echo "Run 'nix fmt .' to format all Nix files"
          echo ""
        '';
      };
    };
}
