{ lib
, runCommand
, writeShellScriptBin
, buildROSEnv
, buildROSWorkspace
, mkShell
, python
, colcon
, rmw-fastrtps-dynamic-cpp
, ros-core
, workspace-autocomplete-setup

, manualDomainId ? builtins.getEnv "NRWS_DOMAIN_ID"
}:

{
  # The name of the workspace.
  name ? "ros-workspace"

  # Configure the workspace for interactive use.
, interactive ? true

, devPackages ? { }
, prebuiltPackages ? { }
, prebuiltShellPackages ? { }
}@args:

let
  domainId = if manualDomainId == "" then 0 else manualDomainId;

  partitionAttrs = pred: lib.foldlAttrs
    (t: key: value:
      if pred key value
      then { right = t.right // { ${key} = value; }; inherit (t) wrong; }
      else { inherit (t) right; wrong = t.wrong // { ${key} = value; }; })
    { right = { }; wrong = { }; };

  # Recursively finds required workspace sibling packages of the given package.
  getWorkspacePackages = package:
    let workspacePackages = package.workspacePackages or { };
    in workspacePackages // getWorkspacePackages' workspacePackages;

  # Recursively finds required workspace sibling packages of the given attribute set of packages.
  getWorkspacePackages' = packages: builtins.foldl' (acc: curr: acc // getWorkspacePackages curr) { } (builtins.attrValues packages);

  # Include standard packages in the workspace.
  standardPackages = {
    inherit ros-core;
  } // lib.optionalAttrs interactive {
    workspace-shell-setup = writeShellScriptBin "mk-workspace-shell-setup"
      # The shell setup script is designed to be sourced.
      # By appearing to generate the script dynamically, this pattern is
      # enforced, as there is no file that can be executed by mistake.
      "cat ${workspace-autocomplete-setup}";
  };

  # Collate the standard and extra prebuilt package sets, and add any sibling packages that they require.
  allPrebuiltPackages =
    standardPackages // prebuiltPackages
    // getWorkspacePackages' (standardPackages // prebuiltPackages // devPackages);

  # Sort packages into various categories.
  splitRosDevPackages = partitionAttrs (name: pkg: pkg.rosPackage or false) (devPackages);
  rosDevPackages = splitRosDevPackages.right;
  otherDevPackages = splitRosDevPackages.wrong;

  splitRosPrebuiltPackages = partitionAttrs (name: pkg: pkg.rosPackage or false) allPrebuiltPackages;
  rosPrebuiltPackages = splitRosPrebuiltPackages.right;
  otherPrebuiltPackages = splitRosPrebuiltPackages.wrong;

  splitPrebuiltShellPackages = partitionAttrs (name: pkg: pkg.rosPackage or false) (prebuiltShellPackages // getWorkspacePackages' prebuiltShellPackages);
  rosPrebuiltShellPackages = splitPrebuiltShellPackages.right;
  otherPrebuiltShellPackages = splitPrebuiltShellPackages.wrong;

  # The shell packages are not included in these sets as they are used only in
  # shell environments.
  rosPackages = rosDevPackages // rosPrebuiltPackages;
  otherPackages = otherDevPackages // otherPrebuiltPackages;

  workspace = (buildROSEnv {
    paths = builtins.attrValues rosPackages;
    postBuild = ''
      rosWrapperArgs+=(--set-default ROS_DOMAIN_ID ${toString domainId})
    '';
  }).override ({ paths ? [ ], passthru ? { }, ... }: {
    # Change the name from the default "ros-env".
    name = "ros-${ros-core.rosDistro}-${name}-workspace";

    # The ROS overlay's buildEnv has special logic to wrap ROS packages so that
    # they can find each other.
    # Unlike the regular buildEnv from Nixpkgs, however, it is designed only with
    # nix-shell in mind, and propagates non-ROS packages rather than including
    # them properly.
    # We must therefore manually add the non-ROS packages to the environment.
    paths = paths ++ builtins.attrValues otherPackages;

    passthru = passthru // {
      inherit
        env
        standardPackages
        devPackages prebuiltPackages
        rosPackages otherPackages;
      inherit (ros-core) rosVersion rosDistro;
    };
  });

  # The workspace shell environment includes non-dev packages as-is as well as
  # build inputs of dev packages.
  #
  # This allows packages to be developed, built and tested with all tools
  # and dependencies available.
  env =
    let
      rosEnv = buildROSEnv {
        wrapPrograms = false;
        paths =
          builtins.attrValues rosPrebuiltPackages
          ++ builtins.attrValues rosPrebuiltShellPackages;
      };
    in
    mkShell {
      name = "${workspace.name}-env";

      packages =
        builtins.attrValues otherPrebuiltPackages
        ++ builtins.attrValues otherPrebuiltShellPackages
        ++ lib.optionals (rosDevPackages != { }) [
          # Add colcon, for building packages.
          # This is a build tool that wraps other build tools, as does Nix, so it is
          # not needed normally in any of the ROS derivations and must be manually
          # added here.
          colcon
        ];

      inputsFrom = [ rosEnv.env ] ++ builtins.attrValues devPackages;

      passthru =
        let
          forDevPackageEnvs = builtins.mapAttrs
            (key: pkg: (buildROSWorkspace (args // {
              name = "${name}-env-for-${pkg.name}";
              devPackages.${key} = pkg;
              prebuiltPackages = args.prebuiltPackages // builtins.removeAttrs args.devPackages [ key ];
            })).env)
            devPackages;
          andDevPackageEnvs = builtins.mapAttrs
            (key: pkg: (buildROSWorkspace (args // {
              name = "${name}-env-and-${pkg.name}";
              devPackages = args.devPackages // { ${key} = pkg; };
              prebuiltPackages = builtins.removeAttrs args.prebuiltPackages [ key ];
            })).env)
            prebuiltPackages;
        in
        {
          inherit workspace rosEnv;

          # Transforms the dev environment to include dependencies for only the selected package.
          for = forDevPackageEnvs;

          # Transforms the dev environment to include dependencies for the existing development packages and the selected package.
          and = andDevPackageEnvs;
        }
        # Pass through "for" and "and" attributes for CLI convenience.
        # They do not conflict, because "for" is generated from devPackages and "and" is generated from prebuiltPackages.
        // forDevPackageEnvs // andDevPackageEnvs;

      shellHook = ''
        # The ament setup hooks and propagated build inputs cause path variables
        # to be set in strange orders.
        # For example, it is common to end up with a regular Python executable
        # in PATH taking priority over the wrapped ROS environment executable.
        #
        # Instead of wrapping executables, set the environment variables
        # directly.
        export LD_LIBRARY_PATH="${rosEnv}/lib:$LD_LIBRARY_PATH"
        export PYTHONPATH="${rosEnv}/${python.sitePackages}:$PYTHONPATH"
        export CMAKE_PREFIX_PATH="${rosEnv}:$CMAKE_PREFIX_PATH"
        export AMENT_PREFIX_PATH="${rosEnv}:$AMENT_PREFIX_PATH"
        export ROS_PACKAGE_PATH="${rosEnv}/share:$ROS_PACKAGE_PATH"

        # Set the domain ID.
        export ROS_DOMAIN_ID=${toString domainId}

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
in
workspace
