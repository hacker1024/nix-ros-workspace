{ nix-ros-overlay ? builtins.fetchTarball "https://github.com/lopsided98/nix-ros-overlay/archive/master.tar.gz"
, overlays ? [ ]
, ...
}@args:

import nix-ros-overlay (args // {
  overlays = [ (import ./overlay) ] ++ overlays;
})
