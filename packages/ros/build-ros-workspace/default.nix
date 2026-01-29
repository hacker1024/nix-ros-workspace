{
  lib,
  writeShellScriptBin,
  buildROSEnv,
  buildROSWorkspace,
  mkShell,
  python,
  colcon,
  ros-core,
  workspace-autocomplete-setup,
}:
let
  envDomainId = builtins.getEnv "NRWS_DOMAIN_ID";
  domainId = if envDomainId == "" then 0 else envDomainId;
in
{
  # The name of the workspace.
  name ? "ros-workspace",

  # Configure the workspace for interactive use.
  interactive ? true,

  devPackages ? { },
  prebuiltPackages ? { },
  prebuiltShellPackages ? { },

  releaseDomainId ? domainId,
  environmentDomainId ? domainId,
  forceReleaseDomainId ? false,

  preShellHook ? "",
  postShellHook ? "",

  extraRosWrapperArgs ? "",
}@args:

let
  partitionAttrs =
    predicate:
    lib.foldlAttrs
      (
        acc: key: value:
        if (predicate key value) then
          {
            right = acc.right // {
              ${key} = value;
            };
            inherit (acc) wrong;
          }
        else
          {
            inherit (acc) right;
            wrong = acc.wrong // {
              ${key} = value;
            };
          }
      )
      # Initial accumulator value
      {
        right = { };
        wrong = { };
      };

  # Check if a package is a ROS package.
  isRosPackage = package: package.rosPackage or false;

  # Recursively finds required dependency workspacePackages of the given package.
  getWorkspacePackages =
    package:
    let
      workspacePackages = package.workspacePackages or { };
    in
    workspacePackages // getWorkspacePackages' workspacePackages;

  # Same as getWorkspacePackages, but takes an attribute set of packages.
  getWorkspacePackages' =
    packages:
    builtins.foldl' (accPkgs: currPkg: accPkgs // (getWorkspacePackages currPkg)) { } (
      builtins.attrValues packages
    );

  # Include standard packages in the workspace.
  standardPackages =
    {
      inherit ros-core;
    }
    // lib.optionalAttrs interactive {
      workspace-shell-setup =
        writeShellScriptBin "mk-workspace-shell-setup"
          # The shell setup script is designed to be sourced.
          # By appearing to generate the script dynamically, this pattern is
          # enforced, as there is no file that can be executed by mistake.
          "cat ${workspace-autocomplete-setup}";
    };

  # Collate the standard and extra prebuilt package sets, and add any sibling packages that they require.
  allPrebuiltPackages =
    standardPackages
    // prebuiltPackages
    // getWorkspacePackages' (standardPackages // prebuiltPackages // devPackages);

  # Sort package groups into ROS and other (non-ROS).
  splitRosDevPackages = partitionAttrs (name: isRosPackage) devPackages;
  rosDevPackages = splitRosDevPackages.right;
  otherDevPackages = splitRosDevPackages.wrong;

  splitRosPrebuiltPackages = partitionAttrs (name: isRosPackage) allPrebuiltPackages;
  rosPrebuiltPackages = splitRosPrebuiltPackages.right;
  otherPrebuiltPackages = splitRosPrebuiltPackages.wrong;

  splitPrebuiltShellPackages = partitionAttrs (name: isRosPackage) (
    prebuiltShellPackages // getWorkspacePackages' prebuiltShellPackages
  );
  rosPrebuiltShellPackages = splitPrebuiltShellPackages.right;
  otherPrebuiltShellPackages = splitPrebuiltShellPackages.wrong;

  # The shell packages are not included in these sets as they are used only in
  # shell environments.
  rosPackages = rosDevPackages // rosPrebuiltPackages;
  otherPackages = otherDevPackages // otherPrebuiltPackages;

  workspace =
    (buildROSEnv {
      paths = builtins.attrValues rosPackages;
      postBuild = ''
        rosWrapperArgs+=(--prefix GZ_SIM_SYSTEM_PLUGIN_PATH : "$out/lib")
        rosWrapperArgs+=(${
          if forceReleaseDomainId then "--set" else "--set-default"
        } ROS_DOMAIN_ID ${toString releaseDomainId})
        rosWrapperArgs+=(${extraRosWrapperArgs})
      '';
    }).override
      (
        {
          paths ? [ ],
          passthru ? { },
          ...
        }:
        {
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
              devPackages
              prebuiltPackages
              rosPackages
              otherPackages
              ;
            inherit (ros-core) rosVersion rosDistro;
          };
        }
      );

  # The workspace shell environment includes non-dev packages as-is as well as
  # build inputs of dev packages.
  #
  # This allows packages to be developed, built and tested with all tools
  # and dependencies available.
  env =
    let
      # Get a flattened list of all attributes named ${name} in the provided package list,
      # which pass the provided filter predicate.
      getFilteredAttrs =
        packages: filter: name:
        builtins.filter filter
          # see mkShell for where this comes from - same pattern as used for inputsFrom
          (lib.flatten (lib.catAttrs name packages));

      # Get all dependencies (recursively) of the provided packages which pass the filter,
      # excluding those in the excludedPkgs list.
      getAllDependencies' =
        filter: packages: excludedPkgs:
        let
          # Get all dependencies of the provided packages which pass the filter.
          allDependencies = builtins.concatMap (getFilteredAttrs packages filter) [
            "buildInputs"
            "nativeBuildInputs"
            "propagatedBuildInputs"
            "propagatedNativeBuildInputs"
          ];
          # We don't want to return the input packages, so add them to the exclude list.
          finalExcludePkgs = packages ++ excludedPkgs;
          # And finally, remove all excluded packages from the output list.
          filteredDependencies = lib.subtractLists finalExcludePkgs allDependencies;
        in
        # Break the recursion if there are no packages to check.
        if packages == [ ] then
          [ ]
        else
          # Add the current dependencies to the list.
          filteredDependencies
          # And also add the dependencies of all the dependencies we just found.
          # Since we exclude the packages we've already found (see finalExcludePkgs),
          # this list will get smaller over time and as such won't recurse infinitely.
          ++ (getAllDependencies' filter filteredDependencies finalExcludePkgs);

      # Get (recursively) all dependencies of the provided packages which pass the provided filter
      getAllDependencies = filter: packages: getAllDependencies' filter packages [ ];

      # Check if a package is a development package.
      isDevPackage = package: builtins.elem package (builtins.attrValues devPackages);
      # Check if a value is:
      # - A derivation - this is needed because some packages depend on a *path* rather than a derivation,
      #   which breaks a whole bunch of logic.
      # - Not a development package.
      # - And is a ROS package - non-ROS packages don't need this workaround.
      isValidRosDependency =
        package: (lib.isDerivation package) && !(isDevPackage package) && (isRosPackage package);

      # List of all ROS build inputs of the ROS packages in development.
      # Normally this is handled entirely using the inputsFrom argument of mkShell,
      # but that breaks some ROS packages which use pluginlib to load libraries from other packages.
      # (notably, robot_state_publisher - it fails to load librobot_state_publisher_node.so)
      # By adding all build inputs to the environment, everything loads correctly.
      allRosDevDependencies = getAllDependencies isValidRosDependency (
        builtins.attrValues rosDevPackages
      );

      rosEnv =
        (buildROSEnv {
          paths =
            builtins.attrValues rosPrebuiltPackages
            ++ builtins.attrValues rosPrebuiltShellPackages
            ++ allRosDevDependencies;
          postBuild = ''
            rosWrapperArgs+=(--prefix GZ_SIM_SYSTEM_PLUGIN_PATH : "$out/lib")
            rosWrapperArgs+=(--set-default ROS_DOMAIN_ID ${toString environmentDomainId})
            rosWrapperArgs+=(${extraRosWrapperArgs})
          '';
        }).override
          (
            { ... }:
            {
              name = "ros-${ros-core.rosDistro}-${name}-shell-env";
            }
          );
    in
    mkShell {
      name = "ros-${ros-core.rosDistro}-${name}-shell";

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

      inputsFrom = [ rosEnv.env ] ++ (builtins.attrValues devPackages);

      passthru =
        let
          forDevPackageEnvs = builtins.mapAttrs (
            key: pkg:
            (buildROSWorkspace (
              args
              // {
                name = "${name}-env-for-${pkg.name}";
                devPackages.${key} = pkg;
                prebuiltPackages = args.prebuiltPackages // builtins.removeAttrs args.devPackages [ key ];
              }
            )).env
          ) devPackages;
          andDevPackageEnvs = builtins.mapAttrs (
            key: pkg:
            (buildROSWorkspace (
              args
              // {
                name = "${name}-env-and-${pkg.name}";
                devPackages = args.devPackages // {
                  ${key} = pkg;
                };
                prebuiltPackages = builtins.removeAttrs args.prebuiltPackages [ key ];
              }
            )).env
          ) prebuiltPackages;
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
        // forDevPackageEnvs
        // andDevPackageEnvs;

      shellHook = ''
        ${preShellHook}
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
        # Create an environment variable pointing to the workspace to allow
        # easy IDE include path configuration.
        export ROS_WORKSPACE_ENV_PATH="${rosEnv}"

        # Set the domain ID.
        export ROS_DOMAIN_ID=${toString environmentDomainId}

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
        ${postShellHook}
      '';
    };
in
workspace
