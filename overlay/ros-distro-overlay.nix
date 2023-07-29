self: super:
rosSelf: rosSuper:

{
  buildROSWorkspace = rosSelf.callPackage ../packages/ros/build-ros-workspace {
    buildEnv = self.buildEnv;
    buildROSEnv = rosSelf.buildEnv;
  };
}
