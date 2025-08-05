{
  description = "dev shell environment for statprint";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    usershell.url = "github:cwndrws/usershell";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    zls = {
      url = "github:zigtools/zls";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-overlay.follows = "zig-overlay";
      };
    };
  };
  outputs = { self, nixpkgs, flake-utils, usershell, zig-overlay, zls, ... }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
          zig-nightly = zig-overlay.packages.${system}.master;
          zls-pkg = zls.packages.${system}.default;
          statprint = pkgs.stdenv.mkDerivation {
            name = "statprint";
            src = self;
            nativeBuildInputs = [zig-nightly];
            preBuild = ''
              export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
              mkdir -p $ZIG_GLOBAL_CACHE_DIR
            '';
            buildPhase = ''
              runHook preBuild
              zig build --release=fast
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp zig-out/bin/statprint $out/bin/statprint
            '';
          };
        in
        {
          devShells.default = usershell.lib.mkUserShell {
            inherit pkgs;
            buildInputs = [ zig-nightly zls-pkg ];
          };
          packages.default = statprint;
        }
      );
}
