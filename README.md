# nix-ros-workspace

An opinionated builder for ROS workspaces using [lopsided98/nix-ros-overlay].

## Quickstart

> [!WARNING]
> To apply any substituter changes and allow binary downloads, you either need to run nix commands with `sudo`, add yourself to [`trusted-users`](https://nix.dev/manual/nix/2.33/command-ref/conf-file.html#conf-trusted-users), or add the cache as a trusted substiter in your Nix config.
> 
> The last option is by far the best, as adding yourself to `trusted-users` is a [massive security risk](https://github.com/NixOS/nix/issues/9649#issuecomment-1868001568).
> However, if you don't apply substituter changes, all software will build locally the first time it's needed.

### Flakes (recommended)

To open a shell with ROS 2 "Jazzy Jalisco", `rviz2`, and `turtlesim` (configured in `flake.nix`):

```console
nix --extra-experimental-features "nix-command flakes" shell github:hacker1024/nix-ros-workspace#turtlesim
```

Once in the shell, run this to set up autocomplete:

```console
eval "$(mk-workspace-shell-setup)"
```

And to build the derivation:

```console
nix --extra-experimental-features "nix-command flakes" build github:hacker1024/nix-ros-workspace#turtlesim
```

### "Classic" Nix

To open a shell with the same configuration as the flake:

```console
$ nix-shell \
  --extra-substituters 'https://ros.cachix.org' --extra-trusted-public-keys 'ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=' \
  https://github.com/hacker1024/nix-ros-workspace/archive/master.tar.gz -A cli.env \
  --argstr distro jazzy \
  --argstr rosPackages 'rviz2 turtlesim'
```

Or, to build a derivation containing all of the above, use `nix-build` and remove the `.env`:

```console
$ nix-build \
  --extra-substituters 'https://ros.cachix.org' --extra-trusted-public-keys 'ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=' \
  https://github.com/hacker1024/nix-ros-workspace/archive/master.tar.gz -A cli \
  --argstr distro jazzy \
  --argstr rosPackages 'rviz2 turtlesim'
```

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

### Flakes

1. Set up [lopsided98/nix-ros-overlay].
2. Add this repository as a flake input.
3. Apply the default overlay after `nix-ros-overlay`: `nix-ros-workspace.overlays.default`

### "Classic" Nix

1. Set up [lopsided98/nix-ros-overlay].
2. Add the overlay from this repository (`(import /path/to/repository { }).overlay`).

## Usage

### API

`buildROSWorkspace` is included in the ROS distro package sets.
The following examples are designed to be invoked with [`callPackage`](https://nixos.org/guides/nix-pills/13-callpackage-design-pattern.html),
e.g.  `rosPackages.rolling.callPackage`.

#### Parameters

`buildROSWorkspace` takes a derivation name, several sets of packages, and a few parameters to create the workspace:

- `devPackages` (package set): Packages that are under active development.
  They will be available in the release environment (`nix-build`),
  but in the development environment (`nix-shell`), only the build inputs of the packages will be available.
- `prebuiltPackages` (package set): Packages that are not under active development (typically third-party packages).
  They will be available in both the release and development environments.
- `prebuiltShellPackages` (package set): Packages that will get added only to the development shell environment.
  This is useful for build tools like GDB.
- `interactive` (boolean): Whether or not the workspace should be configured for interactive use.
  Currently only includes the autocomplete script.
- `releaseDomainId` (integer): Default ROS domain ID in the release environment.
  Can be overridden using the `ROS_DOMAIN_ID` environment variable unless `forceReleaseDomainId` is set.
- `environmentDomainId` (integer): Default ROS domain ID in the development environment.
  Can be overridden using the `ROS_DOMAIN_ID` environment variable.
- `forceReleaseDomainId` (boolean): Whether or not to allow the `ROS_DOMAIN_ID` environment variable to change the domain ID in the production environment.
- `preShellHook` (string): String to insert at the start of the development environment's `shellHook`.
- `postShellHook` (string): String to insert at the end of the development environment's `shellHook`.
- `extraRosWrapperArgs` (string): Extra arguments to pass to the `makeWrapper` call for ROS executables.

Both `releaseDomainId` and `environmentDomainId` will default to the value of the `NRWS_DOMAIN_ID` environment variable at evaluation time [^env-var], or `0` if it is unset.

[^env-var]: However, this requires impure evaluation to take effect.

#### Examples

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
  prebuiltPackages = {
    inherit
      rviz2;
  };
}
```

#### Sibling dependencies

Some packages expect other packages to be available in the workspace, without
depending on them directly. Many launch files, for example, attempt to run
arbitrary nodes and programs.

To accomodate this, the `workspacePackages` passthru attribute is available.
Packages added to this set will be detected by `buildROSWorkspace` and added to
`prebuiltPackages`, along with any `workspacePackages` of their own.

```nix
{ buildRosPackage
, xacro
, gazebo-ros
}:

buildRosPackage {
  # ...
  passthru.workspacePackages = {
    inherit
      xacro
      gazebo-ros;
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