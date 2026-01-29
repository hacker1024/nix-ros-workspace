{
  description = "Workspace builder for ROS based on lopsided98/nix-ros-overlay";

  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs"; # IMPORTANT!!!
  };

  outputs =
    {
      self,
      nix-ros-overlay,
      nixpkgs,
      ...
    }:
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        rosDistro = "jazzy";
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            # add the requisite ROS overlay
            nix-ros-overlay.overlays.default
            # and import our own workspace
            self.overlays.default
          ];
        };
        ros = pkgs.rosPackages.${rosDistro};
      in
      {
        packages = {
          turtlesim = ros.callPackage ros.buildROSWorkspace {
            prebuiltPackages = {
              inherit (ros) turtlesim rviz2;
            };
          };
        };
        formatter = pkgs.nixfmt-tree;
      }
    )
    // {
      overlays = {
        default = (import ./overlay);
      };
    };
  nixConfig = {
    extra-substituters = [
      "https://ros.cachix.org"
    ];
    extra-trusted-public-keys = [
      "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo="
    ];
  };
}
