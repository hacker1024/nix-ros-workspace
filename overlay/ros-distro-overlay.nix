self: super:
rosSelf: rosSuper:

{
  buildROSWorkspace = rosSelf.callPackage ../packages/ros/build-ros-workspace {
    buildROSEnv = rosSelf.buildEnv;
  };
  workspace-autocomplete-setup = rosSelf.callPackage ../packages/ros/workspace-autocomplete-setup { };
}
