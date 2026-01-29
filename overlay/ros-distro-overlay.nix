final: prev: rosFinal: rosPrev: {
  buildROSWorkspace = rosFinal.callPackage ../packages/ros/build-ros-workspace {
    buildROSEnv = rosFinal.buildEnv;
  };
  workspace-autocomplete-setup =
    rosFinal.callPackage ../packages/ros/workspace-autocomplete-setup
      { };
}
