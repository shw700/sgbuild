# sgbuild

An automated subgraph bundle installer.

Default invocation with no parameters fetches everything and builds and installs.

sgbuild.sh should be launched as root in order for the final install process to succeed.
First time users may also need to run first with -d in order to download all other 3rd party library dependency packages.

sgbuild.sh -f simply refreshes the local repos with the latest code from github.
sgbuild.sh -n builds and installs all Subgraph components from the current local code copies.
