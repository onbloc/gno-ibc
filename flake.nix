{
  description = "gno-ibc development environment";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    # Keep `rev` in sync with `.gno-version`'s GNO_COMMIT — `make install-gno`
    # reads that file, the flake input cannot (flake inputs must be literal).
    gno = {
      type = "github";
      owner = "gnolang";
      repo = "gno";
      rev = "e16676eec5f75ab563d4ade83e17d4a96ea04aee";
      flake = false;
    };
    gnopls = {
      type = "github";
      owner = "gnoverse";
      repo = "gnopls";
      rev = "32e82ac207a551ee04fce8559b96e70daca083f9";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, treefmt-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ treefmt-nix.flakeModule ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        { config, self', pkgs, ... }:
        let
          mkGnoTool = args:
            pkgs.buildGo124Module ({
              src = inputs.gno;
              env.CGO_ENABLED = 0;
              doCheck = false;
              meta.mainProgram = args.name;
              ldflags = [
                "-X github.com/gnolang/gno/gnovm/pkg/gnoenv._GNOROOT=${inputs.gno}"
              ];
            } // args);

          gno = mkGnoTool {
            name = "gno";
            vendorHash = "sha256-8kuyN44JcnwTM0z4IdxqMdUMb7zhghfhwMx2UAW/TBw=";
            subPackages = [ "./gnovm/cmd/gno" "./gno.land/cmd/gnokey" ];
          };

          gnodev = mkGnoTool {
            name = "gnodev";
            vendorHash = "sha256-jvPVL8ih6uv/8kuVr+vwmPhO8EYC+3WaWO18RmjXAcg=";
            modRoot = "contribs/gnodev";
          };

          gnopls = pkgs.buildGo125Module {
            name = "gnopls";
            src = inputs.gnopls;
            subPackages = [ "." ];
            vendorHash = "sha256-BD5lx+iTrj4GInH1gIyjj6B+DLPv3VGs5OpnvM0jFok=";
            ldflags = [
              "-X github.com/gnolang/gnoverse/gnopls/pkg/gnotypes._GNOBUILTIN=${inputs.gnopls}/pkg/gnotypes/builtin"
            ];
          };

          pythonEnv = pkgs.python3.withPackages (ps: with ps; [ pytest ]);
        in
        {
          packages = { inherit gno gnopls gnodev; };

          # Limited to packages served by cache.nixos.org so CI setup stays
          # under a minute; gno is built later by `make install-gno`.
          devShells.ci = pkgs.mkShell {
            buildInputs = [ pythonEnv ] ++ (with pkgs; [
              go
              rsync
            ]);
            # `nix print-dev-env` overwrites PATH with the shell's store
            # paths; re-prepend GOBIN so `make verify-gno` finds the gno
            # binary installed there by `make install-gno`.
            shellHook = ''
              export PATH="''${GOBIN:-$HOME/go/bin}:$PATH"
            '';
          };

          devShells.default = pkgs.mkShell {
            inputsFrom = [ self'.devShells.ci ];
            buildInputs = [
              self'.packages.gno
              self'.packages.gnopls
              self'.packages.gnodev
            ]
            ++ (with pkgs; [
              gopls
              gofumpt
              jq
              moreutils
              nixd
            ]);

            nativeBuildInputs = [
              config.treefmt.build.wrapper
            ]
            ++ pkgs.lib.attrsets.attrValues config.treefmt.build.programs;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              gofmt.enable = true;
            };
          };
        };
    };
}
