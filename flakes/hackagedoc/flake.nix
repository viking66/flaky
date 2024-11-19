{
  description = "HackageDoc - A tool for extracting Haskell package documentation";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Separate the runtime dependencies for better maintainability
        runtimeDeps = with pkgs; [
          coreutils
          findutils
          curl
          pandoc
          html-xml-utils
          git
        ];
      in
      {
        packages = rec {
          hackagedoc = pkgs.writeShellApplication {
            name = "hackagedoc";
            runtimeInputs = runtimeDeps;
            text = ''
              set -euo pipefail

              OUTPUT_DIR="output"
              PACKAGE=""
              TEMP_DIR="$(mktemp -d)"
              ORIG_DIR="$(pwd)"
              trap 'rm -rf "$TEMP_DIR"' EXIT

              # Full rainbow gradient (red -> yellow -> green -> cyan -> blue -> magenta)
              color_range=(196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 21 57 93 129 165 201)
              get_gradient_color() {
                  local position=$1
                  local total=$2
                  local index=$(( position * (''${#color_range[@]} - 1) / total ))
                  echo -n $'\033[38;5;'"''${color_range[$index]}"'m'
              }

              show_help() {
                echo "Usage: hackagedoc [OPTIONS] PACKAGE_NAME"
                echo "Options:"
                echo "  -o, --output DIR    Output directory (default: ./output)"
                echo "  -h, --help         Show this help message"
              }

              while [ $# -gt 0 ]; do
                case $1 in
                  -h|--help) show_help; exit 0 ;;
                  -o|--output) OUTPUT_DIR="''${2:-}"; shift 2 ;;
                  -*) echo "Error: Unknown option $1" >&2; show_help; exit 1 ;;
                  *) PACKAGE="$1"; shift ;;
                esac
              done

              [ -z "$PACKAGE" ] && { echo "Error: Package name required" >&2; show_help; exit 1; }

              VERSIONS=$(curl -s "https://hackage.haskell.org/package/$PACKAGE" | 
                        grep -oP '(?<=<a href="/package/'"$PACKAGE"'-)[0-9]+\.[0-9]+(\.[0-9]+)?' | 
                        sort -Vr | uniq)

              [ -z "$VERSIONS" ] && { echo "Error: Package not found" >&2; exit 1; }
              VERSION=$(echo "$VERSIONS" | head -n1)

              TARGET_DIR="$TEMP_DIR/$PACKAGE-$VERSION"
              mkdir -p "$TARGET_DIR"
              
              BASE_URL="https://hackage.haskell.org/package/$PACKAGE-$VERSION"
              DOC_URL="$BASE_URL/docs"

              if ! curl -s "$BASE_URL" > "$TARGET_DIR/index.html"; then
                echo "Error: Failed to download package page" >&2
                exit 1
              fi

              cd "$TARGET_DIR"
              MODULE_PATHS=$(grep -oP '(?<=href="/package/'"$PACKAGE"'-'"$VERSION"'/docs/)[^"]+\.html' "index.html" | sort -u)
              
              [ -z "$MODULE_PATHS" ] && { echo "Error: No modules found" >&2; exit 1; }

              cd "$ORIG_DIR"
              mkdir -p "$OUTPUT_DIR"
              OUTPUT_FILE="$OUTPUT_DIR/$PACKAGE-$VERSION.txt"

              TOTAL_MODULES=$(echo "$MODULE_PATHS" | wc -l)
              COUNT=0
              BAR_WIDTH=30
              RESET=$'\033[0m'

              for path in $MODULE_PATHS; do
                COUNT=$((COUNT + 1))
                PCT=$((COUNT * 100 / TOTAL_MODULES))
                FILLED=$((COUNT * BAR_WIDTH / TOTAL_MODULES))
                EMPTY=$((BAR_WIDTH - FILLED))
                
                # Build gradient progress bar
                GRADIENT_BAR=""
                for i in $(seq 1 $FILLED); do
                  GRADIENT_BAR+="$(get_gradient_color "$i" "$BAR_WIDTH")▇"
                done
                
                printf "\r⚡ [%s%s%s] %s%d%%%s (%d/%d)" \
                  "$GRADIENT_BAR" \
                  "$RESET" \
                  "$(printf '░%.0s' $(seq 1 $EMPTY))" \
                  $'\033[1;36m' "$PCT" "$RESET" \
                  "$COUNT" "$TOTAL_MODULES"
                
                curl -s "$DOC_URL/$path" | 
                  hxselect -c "div.top, div.doc, pre.screen, pre.sourceCode" |
                  pandoc -f html -t plain >> "$OUTPUT_FILE"
                echo -e "\n---\n" >> "$OUTPUT_FILE"
              done

              echo -e "\n$'\033[38;5;118m'✨ Documentation extracted to $OUTPUT_FILE$RESET"
            '';
          };
          default = hackagedoc;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ self.packages.${system}.default ];
          
          # Add development-time dependencies
          nativeBuildInputs = with pkgs; [
            git
            nixpkgs-fmt
            shellcheck  # For shell script linting
          ];
          
          # Add shell hook for better development experience
          shellHook = ''
            echo "🚀 Welcome to HackageDoc development environment!"
            echo "Available commands:"
            echo "  hackagedoc --help    Show usage information"
            echo "  nixpkgs-fmt .        Format Nix files"
            echo "  shellcheck ...       Lint shell scripts"
          '';
        };

        # Add formatter configuration
        formatter = pkgs.nixpkgs-fmt;
        
        # Add checks
        checks.${system} = {
          # Check Nix formatting
          format = pkgs.runCommand "check-format" {
            buildInputs = [ pkgs.nixpkgs-fmt ];
          } ''
            nixpkgs-fmt --check ${./.}
            touch $out
          '';
          
          # Check shell script
          shellcheck = pkgs.runCommand "check-shell" {
            buildInputs = [ pkgs.shellcheck ];
          } ''
            shellcheck ${self.packages.${system}.hackagedoc}/bin/hackagedoc
            touch $out
          '';
        };
      });
}

