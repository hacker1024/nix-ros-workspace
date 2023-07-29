{ lib
, substituteAll
, runCommand
, writeShellScriptBin
, buildEnv
, buildROSEnv
, mkShell
, python
, colcon
, rmw-fastrtps-dynamic-cpp
, ros-core
}:
let
  inherit (python.pkgs)
    argcomplete;
in

{
  # The name of the workspace.
  name

  # Configure the workspace for interactive use.
, interactive ? true

, devPackages ? [ ]
, prebuiltPackages ? [ ]
}:

let
  # Include standard packages in the workspace.
  standardPackages = [
    ros-core
  ] ++ lib.optionals interactive ([
    (writeShellScriptBin "mk-workspace-shell-setup"
      # The shell setup script is designed to be sourced.
      # By appearing to generate the script dynamically, this pattern is
      # enforced, as there is no file that can be executed by mistake.
      "cat ${substituteAll {
            name = "workspace-shell-setup.sh";
            src = ./shell_setup.sh;
            inherit argcomplete;
          }}")
  ]);

  # Sort packages into various categories.
  splitRosPackages = builtins.partition (pkg: pkg.rosPackage or false) (standardPackages ++ devPackages ++ prebuiltPackages);
  rosPackages = splitRosPackages.right;
  otherPackages = splitRosPackages.wrong;

  splitRosPrebuiltPackages = builtins.partition (pkg: pkg.rosPackage or false) (standardPackages ++ prebuiltPackages);
  rosPrebuiltPackages = splitRosPrebuiltPackages.right;
  otherPrebuiltPackages = splitRosPrebuiltPackages.wrong;

  # The ROS overlay's buildEnv has special logic to wrap ROS packages so that
  # they can find each other.
  # Unlike the regular buildEnv from Nixpkgs, however, it is designed only with
  # nix-shell in mind, and propagates non-ROS packages rather than including
  # them properly.
  # We must use a combination of the ROS buildEnv and Nixpkgs buildEnv to
  # include all packages in the environment.
  workspace = buildEnv {
    name = "${name}-workspace";
    paths = [
      (buildROSEnv' { paths = rosPackages; })
    ] ++ otherPackages;
    passthru = {
      inherit
        env
        standardPackages
        devPackages prebuiltPackages
        rosPackages otherPackages;
    };
  };

  # The workspace shell environment includes non-dev packages as-is as well as
  # build inputs of dev packages.
  #
  # This allows packages to be developed, built and tested with all tools
  # and dependencies available.
  env = mkShell {
    name = "${name}-workspace-env";

    packages = otherPrebuiltPackages ++ [
      (buildROSEnv' { paths = rosPrebuiltPackages; })

      # Add colcon, for building packages.
      # This is a build tool that wraps other build tools, as does Nix, so it is
      # not needed normally in any of the ROS derivations and must be manually
      # added here.
      colcon
    ];

    inputsFrom = devPackages;

    shellHook = ''
      ${
        # While the modified version of buildROSEnv contains fixes for ROS
        # packages in the buildROSEnv environment, these do not apply to packages
        # that are being developed and built outside of Nix.
        # The environment must be configured here as well.
        ''
          export RMW_IMPLEMENTATION=rmw_fastrtps_dynamic_cpp
        ''
      }

      # Explicitly set the Python executable used by colcon.
      # By default, colcon will attempt to use the Python executable known at
      # configure time, which does not make much sense in a Nix environment -
      # if the Python derivation hash changes, the old one will still be used.
      export COLCON_PYTHON_EXECUTABLE="${python}/bin/python"

      if [ -z "$NIX_EXECUTING_SHELL" ]; then
        eval "$(mk-workspace-shell-setup)"
      else
        # If a different shell is in use through a tool like https://github.com/chisui/zsh-nix-shell,
        # this hook will not be running in it. "mk-workspace-shell-setup" must be run manually.
        if [ -z "$I_WILL_RUN_WORKSPACE_SHELL_SETUP" ]; then
          echo >&2 'The shell setup script must be manually run.'
          echo >&2 '$ eval "$(mk-workspace-shell-setup)"'
          echo >&2 'Set I_WILL_RUN_WORKSPACE_SHELL_SETUP=1 to silence this message.'
        fi
      fi
    '';
  };

  # A modified version of buildROSEnv that works around
  # lopsided98/nix-ros-overlay#45.
  buildROSEnv' = { paths, postBuild ? "", ... }@args: buildROSEnv (args // {
    paths = paths ++ [ rmw-fastrtps-dynamic-cpp ];
    postBuild = ''
      ${postBuild}
      rosWrapperArgs+=(--set-default RMW_IMPLEMENTATION rmw_fastrtps_dynamic_cpp)
    '';
  });
in
workspace
