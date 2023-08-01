{ lib
, substituteAll
, runCommand
, writeShellScriptBin
, buildEnv
, buildROSEnv
, buildROSWorkspace
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

, devPackages ? { }
, prebuiltPackages ? { }
}@args:

let
  partitionAttrs = pred: lib.foldlAttrs
    (t: key: value:
      if pred key value
      then { right = t.right // { ${key} = value; }; inherit (t) wrong; }
      else { inherit (t) right; wrong = t.wrong // { ${key} = value; }; })
    { right = { }; wrong = { }; };

  # Include standard packages in the workspace.
  standardPackages = {
    inherit ros-core;
  } // lib.optionalAttrs interactive {
    workspace-shell-setup = writeShellScriptBin "mk-workspace-shell-setup"
      # The shell setup script is designed to be sourced.
      # By appearing to generate the script dynamically, this pattern is
      # enforced, as there is no file that can be executed by mistake.
      "cat ${substituteAll {
        name = "workspace-shell-setup.sh";
        src = ./shell_setup.sh;
        inherit argcomplete;
      }}";
  };

  # Sort packages into various categories.
  splitRosDevPackages = partitionAttrs (name: pkg: pkg.rosPackage or false) (devPackages);
  rosDevPackages = splitRosDevPackages.right;
  otherDevPackages = splitRosDevPackages.wrong;

  splitRosPrebuiltPackages = partitionAttrs (name: pkg: pkg.rosPackage or false) (prebuiltPackages // standardPackages);
  rosPrebuiltPackages = splitRosPrebuiltPackages.right;
  otherPrebuiltPackages = splitRosPrebuiltPackages.wrong;

  rosPackages = rosDevPackages // rosPrebuiltPackages;
  otherPackages = otherDevPackages // otherPrebuiltPackages;

  # The ROS overlay's buildEnv has special logic to wrap ROS packages so that
  # they can find each other.
  # Unlike the regular buildEnv from Nixpkgs, however, it is designed only with
  # nix-shell in mind, and propagates non-ROS packages rather than including
  # them properly.
  # We must use a combination of the ROS buildEnv and Nixpkgs buildEnv to
  # include all packages in the environment.
  workspace =
    let
      rosEnv = buildROSEnv' { paths = builtins.attrValues rosPackages; };
    in
    buildEnv {
      name = "${name}-workspace";
      paths = [ rosEnv ] ++ builtins.attrValues otherPackages;
      passthru = {
        inherit
          env
          rosEnv
          standardPackages
          devPackages prebuiltPackages
          rosPackages otherPackages;
        inherit (ros-core) rosVersion rosDistro;
      };
    };

  # The workspace shell environment includes non-dev packages as-is as well as
  # build inputs of dev packages.
  #
  # This allows packages to be developed, built and tested with all tools
  # and dependencies available.
  env =
    let
      rosEnv = buildROSEnv' { paths = builtins.attrValues rosPrebuiltPackages; };
    in
    mkShell {
      name = "${name}-workspace-env";

      packages = (builtins.attrValues otherPrebuiltPackages) ++ [
        rosEnv

        # Add colcon, for building packages.
        # This is a build tool that wraps other build tools, as does Nix, so it is
        # not needed normally in any of the ROS derivations and must be manually
        # added here.
        colcon
      ];

      inputsFrom = builtins.attrValues devPackages;

      passthru =
        let
          devPackageEnvs = builtins.mapAttrs
            (key: pkg: (buildROSWorkspace (args // {
              name = "${name}-env-for-${pkg.name}";
              devPackages.${key} = pkg;
              prebuiltPackages = args.prebuiltPackages // builtins.removeAttrs args.devPackages [ key ];
            })).env)
            devPackages;
        in
        {
          inherit workspace rosEnv;
          for = devPackageEnvs;
        }
        # Pass through "for" attributes for CLI convenience.
        // devPackageEnvs;

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
