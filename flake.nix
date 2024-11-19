{
  description = "Flaky - A collection of helpful Nix flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Individual flakes
    hackagedoc.url = "path:./flakes/hackagedoc";
  };

  outputs = { self, nixpkgs, flake-utils, hackagedoc, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          hackagedoc = hackagedoc.packages.${system}.default;
          
          default = pkgs.symlinkJoin {
            name = "flaky";
            paths = with self.packages.${system}; [
              hackagedoc
            ];
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with self.packages.${system}; [
            hackagedoc
          ];
          
          shellHook = ''
            echo "🌊 Flaky Development Environment"
            echo "Available flakes:"
            echo "  - hackagedoc"
          '';
        };
      });
}
