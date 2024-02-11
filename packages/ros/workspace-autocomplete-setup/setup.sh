# This setup script is designed to be sourced from Bash and Zsh at a minimum.
# It is not in charge of setting up any search paths; that should be done with Nix tooling.

# Set up autocompletion.
if command -v ros2 &> /dev/null; then
  eval "$(@argcomplete@/bin/register-python-argcomplete ros2)"
fi
if command -v colcon &> /dev/null; then
  eval "$(@argcomplete@/bin/register-python-argcomplete colcon)"
fi
if command -v rosidl &> /dev/null; then
  eval "$(@argcomplete@/bin/register-python-argcomplete rosidl)"
fi