final: prev: {
  rosPackages = builtins.mapAttrs (
    rosDistro: rosDistroPackages:
    if rosDistroPackages ? overrideScope then
      rosDistroPackages.overrideScope (import ./ros-distro-overlay.nix final prev)
    else
      rosDistroPackages
  ) prev.rosPackages;
}
