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

`buildROSWorkspace` takes a derivation name and several sets of packages.

`devPackages` are packages that are under active development. They will be
available in the release environment (`nix-build`), but in the development
environment (`nix-shell`), only the build inputs of the packages will be
available.

`prebuiltPackages` are packages that are not under active development (typically
third-party packages). They will be available in both the release and
development environments.

`prebuiltShellPackages` are packages that will get added only to the development
shell environment. This is useful for build tools like GDB.

```nix
{ buildROSWorkspace
, rviz2
, my-package-1
, my-package-2
}:

buildROSWorkspace {
  name = "my";
  devPackages = {
    inherit
      my-package-1
      my-package-2;
  };
  extraPackages = {
    inherit
      rviz2;
  };
}
```

### Command line

The following examples assume a `default.nix` exists, evaluating to the result
of a `buildROSWorkspace` call.

#### Building

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

#### Developing

To enter a shell in the workspace development environment:

```
$ nix-shell -A env

$ # Then, for example:
$ cd ~/ros_ws
$ colcon build
```

##### Composition

###### For

`env` also includes a "sub-environment" for each package in `devPackages`. These
environments are identical to the main environment, but all packages other than
the specified one are moved into `prebuiltPackages`.

In the example below, `my-package-1`'s build dependencies will be available as
normal, but `my-package-2` will be available as if it were in `prebuiltPackages`.

```
$ nix-shell -A env.for.my-package-1
```

###### And

Often, it is useful to work with a subset of the `devPackages`. This can be done by
using the `and` attributes, which move the selected `prebuiltPackages` back into the
`devPackages`.

For example, to work with both `my-package-1` and `my-package-2` as `devPackages`:

```
$ nix-shell -A env.for.my-package-1.and.my-package-2
```

The `.for.my-package-1` moves all but `my-package-1` into `prebuiltPackages`, and the
`.and.my-package-2` brings `my-package-2` back.

These techniques are preferable to `nix-shell -A my-package-1`, as the former will include
standard workspace tools and ROS 2 fixes.

[lopsided98/nix-ros-overlay]: https://github.com/lopsided98/nix-ros-overlay

###### Shortcuts

`for` and `and` can be left out. These two values are the same:

```
env.for.my-package-1.and.my-package-2
```

```
env.my-package-1.my-package-2
```