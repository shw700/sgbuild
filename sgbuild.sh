#!/bin/bash

function display_help {
	echo "Usage: $0 [-c] [-d] [-f [-n]]    where"
	echo "-c   creates a new repository base in the current directory if none exists."
	echo "-d   ensures that all external dependencies for the project are installed."
	echo "-f   only retrieves the freshest copy of each repo."
	echo "-n   builds and installs all existing repos without updating their data."
}

go_build() {
	cd $1 || return 1;

	go $2 $3;

	return $?;
}

# Compare the contents of 2 directories, only checking to see if files that exist in $1 differ in $2
cmp_dirs() {
#	echo "Comparing $1 and $2 ...";

	cd $1 || return 1;

	local i;
	for i in `find * -type f`; do
		diff $i $2/$i >/dev/null 2>/dev/null

		if [ $? -ne 0 ]; then
#			echo "File mismatch: $1/$i vs $2/$i ...";
			return 1;
		fi

	done

	return 0;
}

# Create any local repos that don't exist and clone their contents.
create_repos() {

	for PROJECT in $SUBGRAPH_REPOS; do
		i=`echo $PROJECT | awk -F '/' '{print $NF}'`
		NEXTDIR=$1/$i

		if [ ! -d $NEXTDIR ]; then
			echo "Attempting to clone contents of $i from github ..."
			git clone https://$PROJECT || { echo "Repo clone failed!"; exit 1; }
		fi

	done

}

# Pull the latest contents of all applicable source repos.
freshen_repos() {

	for PROJECT in $SUBGRAPH_REPOS; do
		i=`echo $PROJECT | awk -F '/' '{print $NF}'`
		NEXTDIR=$1/$i

		if [ ! -d $NEXTDIR ]; then
			echo "Error: expected repo directory for $i does not exist; maybe run with -c first?";
			exit 1;
		fi

		pushd $NEXTDIR >/dev/null || { echo "Error changing to directory!"; exit 1; }
		echo "+ Attempting to pull latest contents of repo \"$i\" from github ..."
		git pull || { echo "Repo pull failed!"; exit 1; }
		popd >/dev/null
	done
}

# Install all external dependencies using the package manager.
get_ext_deps() {
	echo "Ensuring presence of external dependencies ..."
	apt-get install libacl1-dev || { echo "Could not install package libacl1-dev for oz build... Failed."; exit 1; }
	echo "+ libacl1-dev OK."
	apt-get install libnetfilter-queue-dev || { echo "Could not install package libnetfilter-queue-dev for oz build... Failed."; exit 1; }
	echo "+ libnetfilter-queue-dev OK."
	echo "Dependencies all OK."
}

# Install the latest copy of program $1 in the working build tree directory into its base directory
install_program() {
	echo "+ $1 ...";
	_PARENT_DIR=`dirname $1`
	_FILENAME=`basename $1`
	cp $i $CURDIR/build/backup/$_FILENAME.`md5sum $i | awk '{print $1}'` || { echo "Unable to make backup copy of $i ... Failing."; exit 1; }
	cp $CURDIR/build/bin/$_FILENAME $_PARENT_DIR/ || { echo "Unable to copy latest version of $_FILENAME into $_PARENT_DIR ... Failing."; exit 1; }
}





CURDIR=`pwd`
DO_CREATE=0
DO_FRESHEN=0
JUST_BUILD=0

if [ `id -u` -ne "0" ]; then
	echo "Warning: it doesn't look like you're running this script as root. It will likely fail."
fi

while getopts "cdfhn" opt; do
	case "$opt" in
	c)
		DO_CREATE=1
		;;
	d)
		get_ext_deps;
		exit 0
		;;
	f)
		DO_FRESHEN=1
		;;
	h)
		display_help
		exit 0
		;;
	n)
		JUST_BUILD=1
		;;
	*)
		display_help
		exit 1
		;;
	esac
done

# orchid, sgmail?
SUBGRAPH_BUILD_DEPENDENCIES="golang.org/x/exp/inotify golang.org/x/sys/unix github.com/op/go-logging github.com/yawning/bulb github.com/TheCreeper/go-notify github.com/codegangsta/cli github.com/BurntSushi/xdg"
SUBGRAPH_BUILD_REPOS="github.com/shw700/tortime github.com/shw700/sublogmon github.com/twtiger/gosecco"
SUBGRAPH_BUILD_REPOS_OTHER="github.com/subgraph/go-procsnitch github.com/subgraph/procsnitchd github.com/subgraph/roflcoptor github.com/subgraph/fw-daemon github.com/subgraph/libmacouflage github.com/subgraph/macouflage github.com/subgraph/macouflage-multi github.com/subgraph/paxrat github.com/subgraph/subgraph_metaproxy github.com/subgraph/go-xdgdirs"
SUBGRAPH_REPOS="$SUBGRAPH_BUILD_REPOS $SUBGRAPH_BUILD_REPOS_OTHER github.com/shw700/sgbuild github.com/shw700/sgconstants github.com/subgraph/oz github.com/subgraph/subgraph_desktop_stretch github.com/subgraph/gnome-shell-extension-torstatus github.com/subgraph/gnome-shell-extension-ozshell github.com/subgraph/subgraph-os-issues github.com/subgraph/subgraph-os-apparmor-profiles github.com/subgraph/sgos_handbook github.com/subgraph/subgraph-archive-keyring github.com/subgraph/subgraph-kernel-configs github.com/subgraph/go-seccomp github.com/subgraph/defector"

if [ $DO_CREATE -eq 1 -a $DO_FRESHEN -eq 1 ]; then
	echo "Error: -c and -f options cannot be passed together.";
	exit 1;
elif [ \( $DO_CREATE -eq 1 -o $DO_FRESHEN -eq 1 \) -a $JUST_BUILD -eq 1 ]; then
	echo "Error: cannot specify -n along with either -c or -f.";
	exit 1;
fi

if [ $DO_CREATE -eq 1 ]; then
	echo "Attempting to create and populate any repos that don't exist ...";
	create_repos $CURDIR;
	echo "Done."
	exit 0;
elif [ $DO_FRESHEN -eq 1 ]; then
	echo "Attempting to freshen all repo data ...";
	freshen_repos $CURDIR;
	echo "Done."
	exit 0;
fi

export GOPATH=$CURDIR/build

if [ $JUST_BUILD -eq 0 ]; then
	create_repos $CURDIR;
	freshen_repos $CURDIR;

	# check to see if the repos exist
	for PROJECT in $SUBGRAPH_REPOS; do
		i=`echo $PROJECT | awk -F '/' '{print $NF}'`

		if [ ! -d $CURDIR/$i ]; then
			echo "Does not seem like repo \"$i\" exists ... failing.";
			echo "Try running $0 -c to create the missing repos for you.";
			exit 1;
		fi

		if [ ! -d $CURDIR/$i/.git ]; then
			echo "Directory exists for \"$i\" exists but it does not seem to be a valid git repository ... failing.";
			echo "Please correct this issue, or delete the directory, and try running this utility again.";
			exit 1;
		fi

	done

	if [ ! -d $CURDIR/build ]; then
		echo "Creating build directory ...";
		mkdir -p $CURDIR/build/src || { echo "Unable to create build directory at $CURDIR/build ... Failing."; exit 1; }
	else
		echo "Making sure that that all build directories are up-to-date ...";
	fi

	echo "Checking to make sure dependencies are up-to-date ...";
	
	for i in $SUBGRAPH_BUILD_DEPENDENCIES; do
		go get $i || { echo "Unable to retrieve go dependency: $i ... Failing."; exit 1; }
		echo "+ $i is OK.";
	done

fi

for i in $SUBGRAPH_BUILD_REPOS $SUBGRAPH_BUILD_REPOS_OTHER; do
	REPO_PATH=`basename $i`

	if [ ! -d $CURDIR/build/src/$i ]; then
		echo "Build directory for $i did not exist ... creating.";
		mkdir -p $CURDIR/build/src/$i || { echo "Unable to create build subdirectory at $CURDIR/build/src/$i ... Failing."; exit 1; }
	fi
		
	echo "Checking to see if build directory for $REPO_PATH is current ...";
	cmp_dirs $CURDIR/$REPO_PATH $CURDIR/build/src/$i

	if [ $? -ne 0 ]; then
		echo "- Directory was not up-to-date ... re-sourcing.";
		rm -rf $CURDIR/build/src/$i || { echo "Unable to remove build subdirectory at $CURDIR/build/src/$i ... Failing."; exit 1; }
		mkdir -p $CURDIR/build/src/$i || { echo "Unable to create build subdirectory at $CURDIR/build/src/$i ... Failing."; exit 1; }
		cp -R $CURDIR/$REPO_PATH/* $CURDIR/build/src/$i || { echo "Unable to copy contents to build subdirectory at $CURDIR/build/src/$i ... Failing."; exit 1; }
	else
		echo "+ Directory is up-to-date.";
	fi

	echo "Building project $i ...";
	go_build $CURDIR/build/src install $i || { echo "Unable to build project at $CURDIR/build/src/$i ... Failing."; exit 1; }

done

if [ -d $CURDIR/build/src/github.com/subgraph/oz ]; then
	echo "Cleaning oz build directory ...";
	rm -rf $CURDIR/build/src/github.com/subgraph/oz || { echo "Unable to clean oz build directory at $CURDIR/build/src/github.com/subgraph/oz ... Failing."; exit 1; }
fi

echo "Done with initial builds... moving to oz."
#exit 1

mkdir -p $CURDIR/build/src/github.com/subgraph/ || { echo "Unable to create staging directory for oz build ... Failing."; exit 1; }
cp -R $CURDIR/oz $CURDIR/build/src/github.com/subgraph/ || { echo "Unable to copy latest oz source to staging directory ... Failing."; exit 1; }

echo "Making sure that subgraph generated constants are up-to-date ...";
GENERATE_CONSTANTS=0
if [ ! -d $CURDIR/build/src/github.com/shw700/constants ]; then
	echo "Constants directory did not exist ... Creating.";
	mkdir -p $CURDIR/build/src/github.com/shw700/constants || { echo "Unable to create constants directory at $CURDIR/build/src/github.com/shw700/constants ... Failing."; exit 1; }
	pushd $CURDIR/sgconstants >/dev/null || { echo "Error changing to directory to constants repo!"; exit 1; }
	GENERATE_CONSTANTS=1
fi

if [ $GENERATE_CONSTANTS -eq 0 ]; then
	pushd $CURDIR/sgconstants >/dev/null || { echo "Error changing to directory to constants repo!"; exit 1; }
	CUR_HASH=`md5sum ./gogen.sh ./getconsts.sh`

	if [ -f $CURDIR/build/src/github.com/shw700/constants/hash ]; then
		LAST_HASH=`cat $CURDIR/build/src/github.com/shw700/constants/hash`

		if [ "$CUR_HASH" != "$LAST_HASH" ]; then
			GENERATE_CONSTANTS=1;
		fi

	else
		GENERATE_CONSTANTS=1;
	fi

fi

if [ $GENERATE_CONSTANTS -eq 0 ]; then
	echo "+ Skipping over constants generation: appears to be up-to-date.";
else
	echo "+ Generating constants ...";
	./gogen.sh > $CURDIR/build/src/github.com/shw700/constants/constants.go || { echo "Unable to create constants definition source file ... Failing."; exit 1; }
	md5sum ./gogen.sh ./getconsts.sh > $CURDIR/build/src/github.com/shw700/constants/hash;
fi

popd >/dev/null;
echo "+ Done."

echo "Building constants definitions ...";
(cd $GOPATH && go install github.com/shw700/constants) || { echo "Unable to build constants definitions ... Failing."; exit 1; }


cd $CURDIR/build/src/github.com/subgraph/oz || { echo "Unable to change directory to oz staging directory ... Failing."; exit 1; }

echo "Building oz subsystem ..."
go install ./... || { echo "go build of oz failed! Exiting"; exit 1; }

echo "Go install succeeded."

OZBINS="/usr/bin/oz /usr/bin/oz-init /usr/bin/oz-mount /usr/bin/oz-seccomp /usr/bin/oz-seccomp-tracer /usr/bin/oz-umount"
OZSBINS="/usr/sbin/oz-daemon /usr/sbin/oz-setup"

echo "Creating backups of oz utilities and replacing them ...";

if [ ! -d $CURDIR/build/backup ]; then
	mkdir $CURDIR/build/backup || { echo "Unable to create backup directory at $CURDIR/build/backup ... Failing."; exit 1; }
fi

for i in $OZBINS; do
	install_program $i
done

for i in $OZSBINS; do
	install_program $i
done

echo "Updating oz profiles ..."
PROFILE_BACKUP=$CURDIR/build/backup/oz_profiles__`date +"%H_%M_%S___%m_%d_%y"`

if [ ! -d $PROFILE_BACKUP ]; then
	mkdir $PROFILE_BACKUP || { echo "Unable to create oz profiles backup directory at $PROFILE_BACKUP ... Failing."; exit 1; }
fi

cp /var/lib/oz/cells.d/*.{json,seccomp} $PROFILE_BACKUP

for i in $CURDIR/oz/profiles/*.{json,seccomp}; do
	PROFDATA=`basename $i`
	diff /var/lib/oz/cells.d/$PROFDATA $CURDIR/oz/profiles/$PROFDATA && continue
	echo "Profile has changed: $PROFDATA"
done


cp /git/oz/profiles/*.{json,seccomp} /var/lib/oz/cells.d || { echo "Unable to update oz profile data in /var/lib/oz/cells.d ... Failing."; exit 1; }

killall -HUP oz-daemon || { echo "Unable to reload OZ daemon."; }

echo "Updating paxrat ..."
install_program /sbin/paxrat

echo "Updating subgraph_metaproxy ..."
install_program /sbin/subgraph_metaproxy

echo "Updating fw-daemon ..."
install_program /usr/sbin/fw-daemon

echo "Updating macouflage ..."
install_program /usr/bin/macouflage

echo "Updating macouflage-multi ..."
install_program /usr/bin/macouflage-multi

echo "Updating sublogmon ..."
install_program /usr/sbin/sublogmon

chown -R user.user $CURDIR/build

echo Done.
