self: super:

{
  rosPackages = builtins.mapAttrs
    (rosDistro: rosDistroPackages:
      if rosDistroPackages ? overrideScope
      then rosDistroPackages.overrideScope (import ./ros-distro-overlay.nix self super)
      else rosDistroPackages)
    super.rosPackages;
}
