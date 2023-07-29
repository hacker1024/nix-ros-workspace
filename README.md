# nix-ros-workspace

An opinionated builder for ROS workspaces using [lopsided98/nix-ros-overlay].

## Rationale

[lopsided98/nix-ros-overlay] provides a variant of `buildEnv` that allows ROS
packages to see each other. This falls short in a few ways, though:

- ROS 2 is not well supported.
- Non-ROS packages added to the environment do not get included outside of `nix-shell`.
- There is no clear way to set up a development environment with a mix of
  prebuilt packages and package build inputs.

The `buildROSWorkspace` function included in this repository aims to solve these
issues.

## Setup

1. Set up [lopsided98/nix-ros-overlay], ensuring that [PR #269](https://github.com/lopsided98/nix-ros-overlay/pull/269) is included.
2. Add the overlay from this repository (`(import /path/to/repository).overlay`).

## Usage

### API

`buildROSWorkspace` is included in the ROS distro package sets. The following
examples are designed to be invoked with [`callPackage`](https://nixos.org/guides/nix-pills/callpackage-design-pattern.html), e.g.
`rosPackages.rolling.callPackage`.

`buildROSWorkspace.explicit` takes a derivation name and two lists of packages.

`devPackages` are packages that are under active development. They will be
available in the release environment (`nix-build`), but in the development
environment (`nix-shell`), only the build inputs of the packages will be
available.

`extraPackages` are packages that are not under active development (typically
third-party packages). They will be available in both the release and
development environments.

```nix
{ buildROSWorkspace
, rviz2
, my-package-1
, my-package-2
}:

buildROSWorkspace.explicit {
  name = "my";
  devPackages = [
    my-package-1
    my-package-2
  ];
  extraPackages = [
    rviz2
  ];
}
```

For finer control over package classification, `buildROSWorkspace` can be used
directly. For example, if the `devPackages` had a `passthru` attribute indicating their
status:

```nix
{ buildROSWorkspace
, rviz2
, my-package-1
, my-package-2
}:

buildROSWorkspace {
  name = "my";
  packages = [
    my-package-1
    my-package-2
    rviz2
  ];
  devPackagePredicate = pkg: pkg.devPackage or false;
}
```

### Command line

The following examples assume a `default.nix` exists, evaluating to the result
of a `buildROSWorkspace` call.

To build a workspace as a regular Nix package:

```
$ nix-build

$ # Then, for example:
$ ./result/bin/ros2 pkg list
```

To enter a shell in the workspace release environment:

```
$ nix-shell -p 'import ./. { }'
$ eval "$(mk-workspace-shell-setup)"

$ # Then, for example:
$ ros2 pkg list
```

To enter a shell in the workspace development environment:

```
$ nix-shell -A env

$ # Then, for example:
$ cd ~/ros_ws
$ colcon build
```

[lopsided98/nix-ros-overlay]: https://github.com/lopsided98/nix-ros-overlay