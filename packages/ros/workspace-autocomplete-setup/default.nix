{ substituteAll
, python3Packages
}:

let
  inherit (python3Packages)
    argcomplete;
in
substituteAll {
  name = "workspace-autocomplete-setup.sh";
  src = ./setup.sh;
  inherit argcomplete;
}
