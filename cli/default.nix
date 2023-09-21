# This function is designed for convenience on the CLI.
# It is not intended to be used programatically.

{ distro, rosPackages ? [ ], otherPackages ? [ ] }:

let
  pkgs = import ./with-overlay.nix { };
  rosPkgs = pkgs.rosPackages.${distro};

  parseList = list:
    if builtins.isList list
    then list
    else pkgs.lib.splitString " " list;
in
rosPkgs.buildROSWorkspace {
  prebuiltPackages =
    (pkgs.lib.genAttrs (parseList rosPackages) (name: rosPkgs.${name})) //
    (pkgs.lib.genAttrs (parseList otherPackages) (name: pkgs.${name}));
}
