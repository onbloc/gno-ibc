{
  unionRoot,
  imageTag,
  revision,
  system ? "x86_64-linux",
}:
let
  union = builtins.getFlake ("path:" + toString unionRoot);
  pkgs = union.inputs.nixpkgs.legacyPackages.${system};
  packages = union.packages.${system};
  scripts = packages.cosmwasm-scripts.union-devnet;
in
pkgs.dockerTools.buildLayeredImage {
  name = "union-deployer";
  tag = imageTag;
  contents = [
    pkgs.cacert
    pkgs.coreutils-full
    packages.cosmwasm-deployer
    scripts.deploy-manager
    scripts.deploy
    scripts.whitelist-relayers
  ];
  config = {
    Cmd = [ "${pkgs.coreutils-full}/bin/true" ];
    Env = [
      "PATH=/bin"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
    Labels = {
      "org.opencontainers.image.revision" = revision;
      "org.opencontainers.image.source" = "https://github.com/onbloc/union-voyager";
    };
    WorkingDir = "/work";
  };
}
