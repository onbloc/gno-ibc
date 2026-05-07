{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    gno = {
      type = "github";
      owner = "gnolang";
      repo = "gno";
      # ref = "feat/cometbls-groth16-verifier";
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
      imports = [
        treefmt-nix.flakeModule
        # To import an internal flake module: ./other.nix
        # To import an external flake module:
        #   1. Add foo to inputs
        #   2. Add foo as a parameter to the outputs function
        #   3. Add here: foo.flakeModule

      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        let
          gno = pkgs.pkgsStatic.buildGo124Module {
            name = "gno";
            src = inputs.gno;
            vendorHash = "sha256-8kuyN44JcnwTM0z4IdxqMdUMb7zhghfhwMx2UAW/TBw=";
            meta = {
              mainProgram = "gno";
            };
            env.CGO_ENABLED = 0;
            doCheck = false;
            subPackages = [ "./gnovm/cmd/gno" "./gno.land/cmd/gnokey" ];
            ldflags = [
              "-X github.com/gnolang/gno/gnovm/pkg/gnoenv._GNOROOT=${inputs.gno}"
            ];
          };
          gnodev = pkgs.pkgsStatic.buildGo124Module {
            name = "gnodev";
            src = inputs.gno;
            vendorHash = "sha256-jvPVL8ih6uv/8kuVr+vwmPhO8EYC+3WaWO18RmjXAcg=";
            meta = {
              mainProgram = "gnodev";
            };
            env.CGO_ENABLED = 0;
            doCheck = false;
            prePatch = ''
              ls -alhL .
              cd ./contribs/gnodev
            '';
            ldflags = [
              "-X github.com/gnolang/gno/gnovm/pkg/gnoenv._GNOROOT=${inputs.gno}"
            ];
          };
          gnopls = pkgs.pkgsStatic.buildGo125Module rec {
            name = "gnopls";
            src = inputs.gnopls;
            subPackages = [ "." ];
            vendorHash = "sha256-BD5lx+iTrj4GInH1gIyjj6B+DLPv3VGs5OpnvM0jFok=";
            ldflags = [
              "-X github.com/gnolang/gnoverse/gnopls/pkg/gnotypes._GNOBUILTIN=${src}/pkg/gnotypes/builtin"
            ];
          };
        in
        {
          # Per-system attributes can be defined here. The self' and inputs'
          # module parameters provide easy access to attributes of the same
          # system.

          # Equivalent to  inputs'.nixpkgs.legacyPackages.hello;
          packages = {
            inherit
              gno
              gnopls
              gnodev
              ;
          };
          devShells = {
            default = pkgs.mkShell {
              buildInputs = [
                self'.packages.gno
                self'.packages.gnopls
                self'.packages.gnodev
              ]
              ++ (with pkgs; [
                go
                gopls
                jq
                moreutils
                nixd
                typescript-language-server
                gofumpt
                python3
                rsync
              ]);
            };
            nativeBuildInputs = [
              config.treefmt.build.wrapper
            ]
            ++ pkgs.lib.attrsets.attrValues config.treefmt.build.programs;
          };

          treefmt = {
            # Used to find the project root
            projectRootFile = "flake.nix";
            programs = {
              nixfmt = {
                enable = true;
                package = pkgs.nixfmt;
              };
              gofmt = {
                enable = true;
              };
            };
          };
        };

      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.
      };
    };
}
