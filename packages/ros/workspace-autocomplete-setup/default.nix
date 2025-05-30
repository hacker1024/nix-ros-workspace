{ replaceVars
, python3Packages
}:

let
  inherit (python3Packages)
    argcomplete;
in
replaceVars ./setup.sh {
  inherit argcomplete;
}
