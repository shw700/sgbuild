#!/bin/bash

function display_help {
	echo "Usage: $0 [-c]   where"
	echo "-c   creates a new repository base in the current directory if none exists."
	echo "-f   only retrieves the freshest copy of each repo."
}

freshen_repos() {

	for i in $SUBGRAPH_REPOS; do
		NEXTDIR=$1/$i

		if [ ! -d $NEXTDIR ]; then
			echo "Attempting to clone contents of $i from github ..."
			git clone https://github.com/subgraph/$i || { echo "Repo clone failed!"; exit 1; }
		else
			pushd $NEXTDIR >/dev/null || { echo "Error changing to directory!"; exit 1; }
			echo "Attempting to pull latest contents of repo \"$i\" from github ..."
			git pull || { echo "Repo pull failed!"; exit 1; }
			popd >/dev/null
		fi

	done

}

CURDIR=`pwd`
DO_CREATE=0

if [ `id -u` -ne "0" ]; then
	echo "Warning: it doesn't look like you're running this script as root. It will likely fail."
fi

while getopts "cdfh" opt; do
	case "$opt" in
	c)
		echo Create
		DO_CREATE=1
		;;
	d)
		echo "Feature not supported yet!"
		exit 0
		;;
	f)
		echo "Feature not supported yet!"
		exit 0
		;;
	h)
		display_help
		exit 0
		;;
	*)
		display_help
		exit 1
		;;
	esac
done

# orchid, sgmail?
SUBGRAPH_REPOS="oz subgraph_desktop_stretch roflcoptor procsnitchd gnome-shell-extension-torstatus fw-daemon go-procsnitch gnome-shell-extension-ozshell subgraph-os-issues subgraph_metaproxy macouflage-multi paxrat subgraph-os-apparmor-profiles sgos_handbook macouflage subgraph-archive-keyring go-xdgdirs subgraph-kernel-configs go-seccomp defector libmacouflage"

if [ $DO_CREATE -eq 1 ]; then
	freshen_repos $CURDIR
fi

# check to see if the repos exist
for i in $SUBGRAPH_REPOS; do

	if [ ! -d $CURDIR/$i ]; then
		echo "Does not seem like repo \"$i\" exists... failing.";
		echo "Try running $0 -c to create the missing repos for you.";
		exit 1;
	fi

	if [ ! -d $CURDIR/$i/.git ]; then
		echo "Directory exists for \"$i\" exists but it does not seem to be a valid git repository... failing.";
		echo "Please correct this issue, or delete the directory, and try running this utility again.";
		exit 1;
	fi

done


if [ ! -d $CURDIR/build ]; then
	echo "Creating build directory...";
	mkdir $CURDIR/build || { echo "Unable to create build directory at $CURDIR/build... Failing."; exit 1; }
else
	echo "Cleaning build directory...";
	rm -rf $CURDIR/build/* || { echo "Unable to clean build directory at $CURDIR/build... Failing."; exit 1; }
fi

mkdir -p $CURDIR/build/src/github.com/subgraph/oz || { echo "Unable to create staging directory for oz build... Failing."; exit 1; }
cp -R $CURDIR/oz $CURDIR/build/src/github.com/subgraph/ || { echo "Unable to copy latest oz source to staging directory... Failing."; exit 1; }

export GOPATH=$CURDIR/build

cd $CURDIR/build/src/github.com/subgraph/oz || { echo "Unable to change directory to oz staging directory... Failing."; exit 1; }

echo "Building oz subsystem..."
go install ./... || { echo "go build of oz failed! Exiting"; exit 1; }

echo "Go install succeeded."

OZBINS="oz oz-init oz-mount oz-seccomp oz-seccomp-tracer oz-umount"
OZSBINS="oz-daemon oz-setup"

echo "Creating backups of oz utilities and replacing them...";

if [ ! -d $CURDIR/build/backup ]; then
	mkdir $CURDIR/build/backup || { echo "Unable to create backup directory at $CURDIR/build/backup... Failing."; exit 1; }
fi

for i in $OZBINS; do
	echo "+ $i ...";
	cp /usr/bin/$i $CURDIR/build/backup/$i.`md5sum /usr/bin/$i | awk '{print $1}'` || { echo "Unable to make backup copy of /usr/bin/$i... Failing."; exit 1; }
	cp $CURDIR/build/bin/$i /usr/bin || { echo "Unable to copy latest version of $i into /usr/bin... Failing."; exit 1; }
done

for i in $OZSBINS; do
	echo "+ $i ...";
	cp /usr/sbin/$i $CURDIR/build/backup/$i.`md5sum /usr/sbin/$i | awk '{print $1}'` || { echo "Unable to make backup copy of /usr/sbin/$i... Failing."; exit 1; }
	cp $CURDIR/build/bin/$i /usr/sbin || { echo "Unable to copy latest version of $i into /usr/sbin... Failing."; exit 1; }
done

echo "Updating oz profiles..."
PROFILE_BACKUP=$CURDIR/build/backup/oz_profiles__`date +"%H_%M_%S___%m_%d_%y"`

if [ ! -d $PROFILE_BACKUP ]; then
	mkdir $PROFILE_BACKUP || { echo "Unable to create oz profiles backup directory at $PROFILE_BACKUP... Failing."; exit 1; }
fi

cp /var/lib/oz/cells.d/*.{json,seccomp} $PROFILE_BACKUP

for i in $CURDIR/oz/profiles/*.{json,seccomp}; do
	PROFDATA=`basename $i`
	diff /var/lib/oz/cells.d/$PROFDATA $CURDIR/oz/profiles/$PROFDATA && continue
	echo "Profile has changed: $PROFDATA"
done


cp /git/oz/profiles/*.{json,seccomp} /var/lib/oz/cells.d || { echo "Unable to update oz profile data in /var/lib/oz/cells.d... Failing."; exit 1; }


chown -R user.user $CURDIR/build
killall -HUP oz-daemon || { echo "Unable to reload OZ daemon."; }


echo Done.
