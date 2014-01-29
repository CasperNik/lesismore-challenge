#!/bin/bash
set -e

# Hello, and welcome to Creatures Docking Station!
#
# If you're looking at this script to see what to do, type
# 	./dstation-install --help
# to find out the parameters you can use.
#
# The Docking Station web site is at
# 	http://ds.creatures.net
#
# Otherwise, you must be looking at this script to see how
# it works.  If you have improvements, please send patches 
# or suggestions to francis.irving@creaturelabs.com.

# Some distributions have this set to a higher security value,
# which would mean users can't read the files that root generates.
umask 022

SYS=linux_x86_glibc21
URL_STUB="http://downloads.ds.creatures.net/installblast/"
DEFAULT_INSTALL_DEST=/usr/local/games/dockingstation
DEFAULT_BIN_DEST=/usr/local/bin
EXECUTE_NAME=dockingstation
BUILD_FILE_PORT=live_$SYS.txt
BUILD_FILE_GLOBAL=dsbuild.bz2.txt

if [ -n "$DS_BETA" ] 
then
	REMOTE_BUILD_FILE_PORT=live_$SYS.beta.txt
	REMOTE_BUILD_FILE_GLOBAL=dsbuild.win32.beta.txt
	BUILD_DESC="Beta latest"
else
	REMOTE_BUILD_FILE_PORT=live_$SYS.txt
	REMOTE_BUILD_FILE_GLOBAL=dsbuild.bz2.txt
	BUILD_DESC=Latest
fi

# Feb. 17, 2000 - Sam Lantinga, Loki Entertainment Software
FindPath()
{
    fullpath="`echo $1 | grep /`"
    if [ "$fullpath" = "" ]; then
        oIFS="$IFS"
        IFS=:
        for path in $PATH
        do if [ -x "$path/$1" ]; then
               if [ "$path" = "" ]; then
                   path="."
               fi
               fullpath="$path/$1"
               break
           fi
        done
        IFS="$oIFS"
    fi
    if [ "$fullpath" = "" ]; then
        fullpath="$1"
    fi
    # Is the awk/ls magic portable?
    if [ -L "$fullpath" ]; then
        fullpath="`ls -l "$fullpath" | awk '{print $10}'`"
    fi
    dirname $fullpath
}

# If launched from a symlink, we know our destination path
[ -L "$0" ] && INSTALL_DEST=`FindPath $0`
[ -L "$0" ] && BIN_DEST=`dirname $0`
# Use default values if the user hasn't set them
[ -z "$INSTALL_DEST" ] && INSTALL_DEST=$DEFAULT_INSTALL_DEST
[ -z "$BIN_DEST" ] && BIN_DEST=$DEFAULT_BIN_DEST

# Check install and bin dest don't have trailing slash
INSTALL_DEST=`echo "$INSTALL_DEST" | sed "s/\/\$//"`
BIN_DEST=`echo "$BIN_DEST" | sed "s/\/\$//"`

# Play hunt Creatures 3
if [ -z "$C3_MAIN" -o ! -d "$C3_MAIN" ]
then
	# Look for a symlink executable
	if type "creatures3" 2>&1 >/dev/null
	then
		C3_BIN=`type -p creatures3`
		C3_MAIN=`FindPath "$C3_BIN"`
	fi
fi
if [ -z "$C3_MAIN" -o ! -d "$C3_MAIN" ]	
then
	# Guess it is in the obvious place
	C3_MAIN=/usr/local/games/creatures3
fi

# Recursive checks
if [ -z "$RECURSIVE" ] 
then
	# Put a blank line (if we haven't run ourself)
	trap echo EXIT
else
	# If root, remove old signal
	rm -f /tmp/dstation_installer_su_ok
fi

# Are we installing off CD or tarball?
if [ -z "$CD_PATH" -a -e "`FindPath $0`/cdtastic" ]
then
	CD_PATH="`FindPath $0`"
	# Make absolute
	if ! echo "$CD_PATH" | egrep "^/" >/dev/null
	then
		CD_PATH="`pwd`/$CD_PATH"
	fi
	# Strip slash
	CD_PATH=`echo "$CD_PATH" | sed "s/\/\$//"`
fi

# Put a blank line when script ends
trap interrupted SIGINT

# Remember what we are, so we can relaunch ourself
SELF=$0
SELF_PARAMETERS=$@
BASH_SWITCH=""

function interrupted()
{
	echo 
	echo "Script interrupted!"
	echo
	echo "You can resume the installation by running the script"
	echo "again, or by typing 'dockingstation' if the installation"
	echo "has got far enough."

	exit 1
}

# Cope with Slackware, which doesn't have mktemp
function make_temp_file()
{
	if type mktemp 2>/dev/null >/dev/null
	then
		TEMP_FILE=`mktemp /tmp/$BUILD_FILE_GLOBAL.XXXXXX`
	else
		TEMP_FILE=/tmp/$BUILD_FILE_GLOBAL.$$
		touch $TEMP_FILE
	fi
}

# Print message when not connected to internet
function download_fail()
{
	if [ -e "$INSTALL_DEST/$BUILD_FILE_PORT" ] && [ -e "$INSTALL_DEST/$BUILD_FILE_GLOBAL" ]
	then
		echo
		echo "Docking Station failed to update from the internet. Either you"
		echo "are not connected to the internet or the update server is down."
		echo "Please connect to the internet and try again."
		echo
		echo "You can run the game without checking for updates by typing"
		echo -ne '\033]0;\w\007\033[32mdockingstation nocheck\033[0m'
		echo ". Note: You need to connect to the internet"
		echo "anyway to make a new world once the game has started."
	else
		echo
		echo "Docking Station failed to install from the internet. Either you"
		echo "are not connected to the internet or the update server is down."
		echo "Please connect to the internet and try again, or try again later."
	fi

	exit 1
}

# $1 - Remote file name relative to URL_STUB
# $2 - Local file name
function download()
{
	rm -f "$2"

	if [ -z "$CD_PATH" ]
	then
		if type wget 2>/dev/null >/dev/null
		then
			# If we get failure, we try again verbosely so the
			# user can see the error
			if ! wget --cache=off -q -O "$2" "$URL_STUB$1"
			then 
				if ! wget --cache=off -O "$2" "$URL_STUB$1"
				then
					echo Error performing wget
					download_fail
				fi
			fi
		elif type lynx 2>/dev/null >/dev/null
		then
			ESCAPED_URL=`echo $URL_STUB$1 | sed "s/ /%20/g"`
			if ! lynx -source "$ESCAPED_URL" >"$2"
			then
				echo Error performing lynx get
				download_fail
			fi
		else
			echo "You need either wget (preferably) or lynx installed."
			echo "These are standard pieces of software which you should"
			echo "be able to install using the normal method for your"
			echo "distribution."
			exit 1
		fi
	else
		# Install from CD or tarball
		cp "$CD_PATH/$1" "$2"
	fi
}

# $1 - Local file without compression extension to uncompress
function decompress()
{
	rm -f "$1"
	if ! type bunzip2 2>/dev/null >/dev/null
	then
		echo
		echo "You need to have bunzip2 installed.  Bzip2 is a"
		echo "trendy new compression program, which is starting"
		echo "to replace gzip.  It has similar command line and"
		echo "library features to gzip/zlib, but better compression."
		echo
		echo "Docking Station's download for Windows was reduced in"
		echo "size from 27Mb to 20Mb using bzip2, as compared to gzip."
		echo 
		echo "You should be able to install it using the normal"
		echo "method for your distribution."
		exit 1
	fi
	bunzip2 "$1.bz2"
}

# $1 - Path to write to
function check_writeable()
{
	if [ ! -d "$1" ]
	then
		echo "Directory $1 doesn't exist, or is a file."
		echo "You could try making it and running the script again."
		exit 1
	fi
	if [ ! -w "$1" ]
	then
		echo "You do not have write access to $1"
		if [ "$DEFAULT_INSTALL_DEST" = "$INSTALL_DEST" ]
		then
			echo
			echo "(You can install to your home directory by setting"
			echo "INSTALL_DEST to a path before running this script."
			echo "e.g. INSTALL_DEST=~/DockingStation BIN_DEST=~/bin $0)"
			echo
		fi
		echo "Rerunning installation script as root"

		# Terrible hack to pass info back from SU.  We just
		# need the return code of the script run as SU, but
		# SU doesn't return it.
		if ! su --shell=/bin/bash -c "RECURSIVE=true CD_PATH=\"$CD_PATH\" sh $BASH_SWITCH \"$SELF\" $SELF_PARAMETERS"
		then
			# Try again with a vanilla version of su
			echo "Failed to run \"su\" with --shell.  This could be because"
			echo "you got the password wrong, or it could be because su"
			echo "does not support the --shell option on your distribution."
			echo
			echo "Trying again without --shell.  If you are using a "
			echo "shell other than bash as your standard shell then "
			echo "you may have problems.  If so, either upgrade to "
			echo "a more recent version of \"su\" or change root's shell"
			echo "to be bash."
			echo 
			if ! su -c "RECURSIVE=true CD_PATH=\"$CD_PATH\" sh $BASH_SWITCH \"$SELF\" $SELF_PARAMETERS"
			then
				echo
				echo "Failed to launch \"su\" for some reason.  Try running \"su\" "
				echo "first to become root before starting the installation."
				exit 1
			fi
	   	fi
		
		if [ -e /tmp/dstation_installer_su_ok ]
		then
			# Run self as normal user to carry on with installation
			echo "Rerunning self as normal user"
			env RECURSIVE= CD_PATH="$CD_PATH" sh $BASH_SWITCH "$SELF" $SELF_PARAMETERS
			exit $?
		else
			exit 1
		fi
	fi
	
}

# magic_echo and magic_unecho write out text to a line,
# and can undo the output using carriage returns and spaces.
# $@ - Text to echo
COLUMNS=`tput cols`
function magic_echo()
{
	VALUE="$@"
	# If we go beyond the line end, then wrap
	NEW_SIZE=$((CHAR_COUNT+${#VALUE}+1)) 
	if [ $NEW_SIZE -lt $COLUMNS ]
	then
		# Print our text, recording its length
		echo -n "$@ "
		CHAR_COUNT=$((CHAR_COUNT+${#VALUE}+1))
	fi
}

# No parameters
function magic_unecho()
{
	# Print spaces to wipe out what was magically echoed
	echo -ne "\r"
	head -c$CHAR_COUNT /dev/zero | tr "\000" " "
	echo -ne " \r"
	CHAR_COUNT=0
}

# $1 - Location under URL_STUB of file list to get
# $2 - Size of file fed into stdin
# stdin - File list to process
function process_file_list_download
{
	COUNT=0
	while read FULL_SIZE SQUASH_SIZE REMOTE_SUM FILE_NAME
	do
		LOWER_FILE_NAME=`echo $FILE_NAME | perl -pe 'm/(Sounds\/|Backgrounds\/|Overlay Data\/|Body\ Data\/|Images\/)(.*)/ and $_ = $1 . lc($2) . "\n"'`

		COUNT=$((COUNT+1))
		magic_echo "$COUNT/$2 $FILE_NAME ..."
		if [ "$REMOTE_SUM" = "Delete" ]
		then
			magic_echo "going"
			if [ "$LOWER_FILE_NAME" != "." ]
			then
				if [ -d "$LOWER_FILE_NAME" ]
				then
					rmdir --ignore-fail-on-non-empty "$LOWER_FILE_NAME"
				else
					rm -f "$LOWER_FILE_NAME"
				fi
			fi
		elif [ "$REMOTE_SUM" = "Directory" ] 
		then
			magic_echo "making directory"
			mkdir -p "$FILE_NAME"
		else
			LOCAL_SUM=""
			if [ -e "$LOWER_FILE_NAME" ]
			then
				magic_echo "checking ..."
				LOCAL_SUM=`md5sum -b "$LOWER_FILE_NAME" 2>&1 | cut "-d " -f1`
			fi
			if [ "$REMOTE_SUM" != "$LOCAL_SUM" ]
			then
				if [ -z "$CD_PATH" ]
				then
					magic_echo "downloading ..."
				else
					magic_echo "copying ..."
				fi
				download "$1$FILE_NAME.bz2" "$LOWER_FILE_NAME.bz2"
				decompress "$LOWER_FILE_NAME"
				magic_echo "verifying ..."
				LOCAL_SUM=`md5sum -b "$LOWER_FILE_NAME" | cut "-d " -f1`
				if [ "$REMOTE_SUM" != "$LOCAL_SUM" ]
				then
					echo "failed"
					echo "Checksum failed after download of $FILE_NAME"
					echo "Remote sum: *$REMOTE_SUM* Local sum: *$LOCAL_SUM*"
					exit 1
				fi
				magic_echo "chmod ..."
				# Execute permissions to shared objects, and executables
				echo $LOWER_FILE_NAME | egrep "\.so|lc2e|^langpick$|^imageconvert$|^dstation-install$" >/dev/null && chmod a+x "$LOWER_FILE_NAME"
			fi
			magic_echo "ok"
		fi
		magic_unecho
	done
}

# $1 - Size of file fed into stdin
# stdin - File list to process
function process_file_list_uninstall
{
	COUNT=0
	while read FULL_SIZE SQUASH_SIZE REMOTE_SUM FILE_NAME
	do
		LOWER_FILE_NAME=`echo $FILE_NAME | perl -pe 'm/(Sounds\/|Backgrounds\/|Overlay Data\/|Body\ Data\/|Images\/)(.*)/ and $_ = $1 . lc($2) . "\n"'`

		COUNT=$((COUNT+1))
		magic_echo "$COUNT/$1 $FILE_NAME ..."
		if [ "$REMOTE_SUM" = "Directory" ] 
		then
			magic_echo "removing ..."
			if [ "$FILE_NAME" != "." ]
			then
				[ -e "$FILE_NAME" ] && rmdir --ignore-fail-on-non-empty "$FILE_NAME"
			fi
			magic_echo "ok"
		elif [ "$REMOTE_SUM" != "Delete" ] 
		then
			magic_echo "deleting ..."
			rm -f "$LOWER_FILE_NAME"
			rm -f "$LOWER_FILE_NAME.bz2"
			magic_echo "ok"
		fi
		magic_unecho
	done
}

# $1 - Location under URL_STUB of file list to get
# $2 - Name of file list index
function download_file_list()
{
	echo
	echo Getting files from $1 to `pwd`
	download "$1$2.bz2" "$2.bz2"
	decompress "$2"

	cat $2 | tr -d "\r" | process_file_list_download "$1" `wc --lines $2`
}

# $1 - Name of file list index
function uninstall_file_list()
{
	echo
	echo Uninstalling files from $1 in `pwd`
	[ -e $1 ] || return
	# I'm proud of finding a real use for tac
	tac $1 | tr -d "\r" | process_file_list_uninstall `wc --lines $1`
	rm -f $1
}

function show_license()
{
	fold -s <<END | more

Hello, and welcome to Creature Docking Station!  Before we can carry on, we
have to make sure you agree to a license.  Press space to read through the
license, then type "yes" to continue installation.

End-User Software License Agreement

THIS AGREEMENT IS A LEGAL DOCUMENT. READ IT CAREFULLY BEFORE COMPLETING THE INSTALLATION PROCESS OR USING THE SOFTWARE. IT PROVIDES A LICENSE TO USE THE SOFTWARE AND CONTAINS WARRANTY INFORMATION AND LIABILITY DISCLAIMERS.

BY INSTALLING OR USING THE SOFTWARE, YOU ARE CONFIRMING ACCEPTANCE OF THE SOFTWARE AND AGREEING TO BECOME BOUND BY THE TERMS OF THIS AGREEMENT.   IF YOU DO NOT WISH TO ACCEPT THE SOFTWARE OR DO NOT AGREE TO THE TERMS OF THIS AGREEMENT: (1) DO NOT COMPLETE THE INSTALLATION PROCESS OR USE THE SOFTWARE; AND (2) DO DELETE THE SOFTWARE AND ALL RELATED FILES FROM YOUR COMPUTER.  IF YOU HAVE COMPLIED WITH THE PRECEDING POINTS (1) AND (2) YOU MAY CONTACT CYBERLIFE TECHNOLOGY LIMITED FOR A FULL REFUND OF THE AMOUNT YOU PAID.

1. LICENCE: This End-User Software Licence Agreement ("EUSLA") allows you to install and use the computer software in this product ("the Software") on a single computer and make one copy of the Software in machine-readable form solely for backup purposes [upon receipt of purchase price].  You must reproduce on any such copy all copyright notices and any other proprietary legends from the original copy of the Software.

You may transfer the Software, but only if the recipient agrees to accept all of the terms and conditions of this EUSLA.   If you do transfer the Software, you must transfer all components and documentation and erase any copies residing on your computer.  Your licence is automatically terminated if you transfer the Software.

2. LICENCE RESTRICTIONS: Other than as set forth in paragraph 1, you may not:

(a) make or distribute copies of the Software;
(b) electronically transfer the Software from one computer to another or over a network;
(c) decompile, reverse-engineer, disassemble, or otherwise reduce the Software to a human-perceivable form;
(d) rent, lease or sublicense the Software;
(e) modify the Software or create derivative works based upon the Software.

3. OWNERSHIP:  The foregoing licence gives you limited rights to use the Software. Although you own the media on which the Software is recorded, you do not become the owner of, and CyberLife Technology Limited ("CyberLife") retains title to, the Software and all copies thereof.  All rights not specifically granted in this EUSLA, including all the UK, US and world-wide copyright, are reserved by CyberLife.

4. LIMITED WARRANTY:  CyberLife warrants to the original consumer purchaser that the media on which the Software is recorded is free from defects in materials and workmanship for a period of ninety (90) days from the date of purchase (as evidenced by your receipt or by our records).   Except for the limited ninety (90) days warranty on the media, the Software and any related documentation or materials are provided "as is" and without warranty of any kind.

5. NO OTHER WARRANTY:  Except as stated in paragraph 4, this Software is provided without warranty of any kind, express or implied, statutory or otherwise, and all such warranties, terms and conditions are expressly excluded, including, but not limited to, any implied warranties, terms or conditions of satisfactory quality, merchantability and fitness for a particular purpose.  The entire risk as to the quality and performance of the Software is with you.   Should the Software prove defective, you assume the entire cost of all necessary servicing, repair or correction. CyberLife does not warrant that the functions contained in the Software will meet your requirements or that the operation of the Software will be uninterrupted or error-free. 

(USA only)  SOME STATES DO NOT ALLOW THE EXCLUSION OF IMPLIED WARRANTIES, SO THE ABOVE EXCLUSION MAY NOT APPLY TO YOU.  THIS WARRANTY GIVES YOU SPECIFIC LEGAL RIGHTS AND YOU MAY ALSO HAVE OTHER LEGAL RIGHTS WHICH VARY FROM STATE TO STATE.

6. EXCLUSIVE REMEDY: Your exclusive remedy under this EUSLA is to return the Software to the place you acquired it, with proof of purchase and a description of the problem. CyberLife will use reasonable commercial efforts to supply you with a replacement copy of the Software that substantially conforms to the documentation or refund to you your purchase price for the Software, at its option.   This remedy will not be available and CyberLife shall have no responsibility if the Software has been altered in any way, if the media has been damaged by accident, abuse or misapplication, or if the failure arises out of use of the Software with other than a recommended hardware configuration.

7. LIMITATION OF LIABILITY: CYBERLIFE'S SOLE LIABILITY TO YOU FOR ANY CLAIM, DEMAND OR CAUSE OR ACTION WHATSOEVER, AND REGARDLESS OF FORM OF ACTION, WHETHER IN CONTRACT OR TORT, INCLUDING NEGLIGENCE, IS SET OUT IN PARAGRAPH 6 ABOVE.   IN NO EVENT SHALL CYBERLIFE BE LIABLE FOR OR YOU HAVE A REMEDY FOR RECOVERY OF ANY SPECIAL, INDIRECT, INCIDENTAL OR CONSEQUENTIAL DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF DATA, LOST PROFITS, LOST SAVINGS, LOST REVENUES OR ECONOMIC LOSS OF ANY KIND, OR FOR ANY CLAIM BY ANY THIRD PARTY EVEN IF CYBERLIFE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

8. DEATH AND PERSONAL INJURY:  The exclusions and limitations on CyberLife's liability to you shall not apply to death or personal injury caused by the negligence of CyberLife or its employees.

9. BASIS OF BARGAIN: The limited warranty, exclusive remedies and limited liability set forth above are fundamental elements of the basis of the agreement between CyberLife and you. You acknowledge that CyberLife would not be able to provide the Software on an economic basis without such limitations.

10. GENERAL: If any provision of this EUSLA is determined to be invalid or unenforceable, it shall be deemed to be omitted and the remaining provisions shall continue in full force and effect. CyberLife's waiver of any right shall not constitute a waiver of that right in the future. This Agreement shall be governed and construed in accordance with the laws of England. You agree to indemnify CyberLife to twice all costs should out-of-jurisdiction action be required, sought or imposed in or from non-English courts. This Agreement constitutes the entire understanding between the parties with respect to the subject matter hereof and all prior agreements, representations, statements and undertakings, oral or written, are hereby expressly superseded and cancelled.

Type "yes" to confirm you agree to this license, or anything else to stop
the installation.
END
	INPUT=""
	while [ "$INPUT" != "yes" ]
	do
		# Old versions of Bash (e.g. on RedHat 6.1) don't have "read -e", so we
		# try again without it if it fails.
		read -e INPUT || read INPUT
		echo
		if [ "$INPUT" = "no" ]
		then
			echo "Sorry, but we had to ask to cover our backs."
			echo "We hope you come back again!"
			exit 1
		elif [ "$INPUT" != "yes" ]
		then
			echo "Please enter \"yes\" or \"no\""
		fi
	done
	echo "Thank you! Now we can start installing..."
	echo
}

function update()
{
	echo
	echo "Docking Station InstallBlast"
	echo "----------------------------"
	echo
	
	[ ! -z "$CD_PATH" ] && echo -e "Installing off filesystem $CD_PATH\n"

	if [ -e "$INSTALL_DEST" ]
	then
		echo "Checking for updates..."
		echo 
	fi
	update_port
	make_bin_link
	echo 
	update_global
	echo

	if [ ! -z "$CD_PATH" -a -z "$RECURSIVE" ]
	then
		echo -ne "Rerunning to check for "
		echo -ne '\033]0;\w\007\033[32mnetwork updates\033[0m'
		echo
		cd $INSTALL_DEST
		env RECURSIVE= CD_PATH= sh $BASH_SWITCH dstation-install $SELF_PARAMETERS
		exit $?
	fi
}

function update_global()
{
	# Find current global build number
	if [ -e "$INSTALL_DEST/$BUILD_FILE_GLOBAL" ]
	then
		CURRENT_BUILD_GLOBAL=`cat $INSTALL_DEST/$BUILD_FILE_GLOBAL | tr -d "\r"`
	else
		CURRENT_BUILD_GLOBAL=""
	fi

	# Get latest global build number from server
	make_temp_file
	download $REMOTE_BUILD_FILE_GLOBAL $TEMP_FILE
	LATEST_BUILD_GLOBAL=`cat $TEMP_FILE | tr -d "\r"`
	rm -f $TEMP_FILE
	echo Current global build: $CURRENT_BUILD_GLOBAL
	echo $BUILD_DESC global build: $LATEST_BUILD_GLOBAL

	if [ "$CURRENT_BUILD_GLOBAL" = "$LATEST_BUILD_GLOBAL" ] 
	then
		echo Nothing to update globally
		return
	fi
	echo Updating to latest version

	# Make the directory, and check we can write to it
	check_writeable `dirname "$INSTALL_DEST"`
	mkdir -p "$INSTALL_DEST"
	check_writeable "$INSTALL_DEST"
	cd "$INSTALL_DEST"

	# Mark that our build is in an intermediate state
	echo > $INSTALL_DEST/$BUILD_FILE_GLOBAL

	if [ -d "Images" -o -d "Backgrounds" ]
	then
		echo Converting images for checksumming
		./imageconvert -16 Images/* Backgrounds/*
	fi

	echo Updating global data to latest version
	download_file_list "$LATEST_BUILD_GLOBAL/global/" file_list.txt .

	echo Converting images to local format
	./imageconvert Images/* Backgrounds/*

	echo $LATEST_BUILD_GLOBAL > $INSTALL_DEST/$BUILD_FILE_GLOBAL
	echo Finished global update
}

function update_port()
{
	# Find current port build number
	if [ -e "$INSTALL_DEST/$BUILD_FILE_PORT" ]
	then
		CURRENT_BUILD_PORT=`cat $INSTALL_DEST/$BUILD_FILE_PORT | tr -d "\r"`
	else
		CURRENT_BUILD_PORT=""
	fi

	# Get latest global build number from server
	make_temp_file
	download ports/$REMOTE_BUILD_FILE_PORT $TEMP_FILE
	LATEST_BUILD_PORT=`cat $TEMP_FILE | tr -d "\r"`
	rm -f $TEMP_FILE
	echo Current $SYS build: $CURRENT_BUILD_PORT
	echo $BUILD_DESC $SYS build: $LATEST_BUILD_PORT

	if [ "$CURRENT_BUILD_PORT" = "$LATEST_BUILD_PORT" ] 
	then
		echo Nothing to update for $SYS
		return
	fi
	echo Updating to latest version

	OUR_SUM=`md5sum -b "$SELF"`

	# Make the directory, and check we can write to it
	check_writeable `dirname "$INSTALL_DEST"`

	# We are root now, and the script won't be relaunched
	# before the directory is made, so if it is not there
	# we do a license prompt.
	[ ! -e "$INSTALL_DEST" ] && show_license

	# Make the directory, and check it is writeable
	mkdir -p "$INSTALL_DEST"
	check_writeable "$INSTALL_DEST"
	cd "$INSTALL_DEST"

	# Mark that our build is in an intermediate state
	echo > $INSTALL_DEST/$BUILD_FILE_PORT

	echo Updating $SYS to latest version
	download_file_list "ports/$LATEST_BUILD_PORT/" file_list_$SYS.txt .
	echo $LATEST_BUILD_PORT > $INSTALL_DEST/$BUILD_FILE_PORT
	echo Finished $SYS update

	# See if we need to relaunch ourself
	NEW_SUM=`md5sum -b "$INSTALL_DEST/dstation-install"`
	if [ "$NEW_SUM" != "$OUR_SUM" ]
	then
			echo "Relaunching new version of script"
			env CD_PATH="$CD_PATH" sh $BASH_SWITCH "$INSTALL_DEST/dstation-install" $SELF_PARAMETERS
			exit $?
	fi
}

function make_bin_link()
{
	# If an existing symbolic link, check it goes to the same place
	if [ -L "$BIN_DEST/$EXECUTE_NAME" ]
	then
        LINK_NAME="`ls -l "$BIN_DEST/$EXECUTE_NAME" | awk '{print $10}'`"
		if [ "$LINK_NAME" != "$INSTALL_DEST/dstation-install" ]
		then
			echo
			echo "File $BIN_DEST/$EXECUTE_NAME is already a symbolic"
			echo "link to a different place.  The installer is trying"
			echo "to make a link to $INSTALL_DEST/dstation-install."
			echo "The current link is:"
			echo
			ls -l $BIN_DEST/$EXECUTE_NAME
			echo
			echo "Either delete this link, or install the link to"
			echo "another directory by setting BIN_DEST to a path"
			echo "before running this script."
			echo
			echo "e.g. INSTALL_DEST=~/DockingStation BIN_DEST=~/bin $0"
			echo
			exit 1
		fi

		# Link is fine, so return
		return
	fi

	# If a file is in the way, complain
	if [ -e "$BIN_DEST/$EXECUTE_NAME" ]
	then
		echo
		echo "File $BIN_DEST/$EXECUTE_NAME is in the way."
		ls -l $BIN_DEST/$EXECUTE_NAME
		echo
		echo "(Install the link to another directory by setting"
		echo "BIN_DEST to a path before running this script."
		echo "e.g. INSTALL_DEST=~/DockingStation BIN_DEST=~/bin $0)"
		echo
		exit 1
	fi

	# Nothing there, so make our link
	echo
	echo Making \'dockingstation\' executable link...
	check_writeable "$BIN_DEST"
	ln -s "$INSTALL_DEST/dstation-install" "$BIN_DEST/$EXECUTE_NAME"
}

function uninstall()
{
	echo
	echo "Docking Station uninstaller"
	echo "---------------------------"

	if [ ! -e "$INSTALL_DEST" ]
	then
		echo
		echo Docking Station is not installed at $INSTALL_DEST
		exit 1
	fi

	check_writeable `dirname "$INSTALL_DEST"`
	check_writeable "$INSTALL_DEST"
	check_writeable "$BIN_DEST"

	# Mark that our build is in an intermediate state
	echo > $INSTALL_DEST/$BUILD_FILE_GLOBAL
	echo > $INSTALL_DEST/$BUILD_FILE_PORT

	cd "$INSTALL_DEST"
	rm -f wget-log
	uninstall_file_list file_list.txt .
	rm -f "$BUILD_FILE_GLOBAL"
	uninstall_file_list file_list_$SYS.txt .
	rm -f "$BUILD_FILE_PORT"
	cd ~
	rmdir --ignore-fail-on-non-empty "$INSTALL_DEST"

	if [ -L "$BIN_DEST/$EXECUTE_NAME" ]
	then
		echo "Removing symbolic link $BIN_DEST/$EXECUTE_NAME"
		rm "$BIN_DEST/$EXECUTE_NAME"
	fi	

	echo Finished uninstallation
}

function user_launch()
{
	if [ -z "$REALLY_RUN_AS_ROOT" ]
	then
		if whoami | egrep "^root$" > /dev/null
		then
			# Break out of being root, by recursing
			if [ ! -z "$RECURSIVE" ] 
			then
				# Search above for explanation of this file
				touch /tmp/dstation_installer_su_ok
				exit 0
			fi
			echo "WARNING: You are trying to run the game as root."
			echo "This is probably not advisable.  Log in as a normal"
			echo "user and type 'dockingstation' to try again, or"
			echo "set the environment variable REALLY_RUN_AS_ROOT"
			echo "if you really want to."
			echo
			exit 1
		fi
	fi

	DS_HOME=$HOME/.dockingstation
	DS_MAIN=$INSTALL_DEST

	# Make sure all the directories are there
	if [ ! -d "$DS_HOME" ]; then
		echo "Making home directory $DS_HOME"

		# Make all directories
		mkdir "$DS_HOME"
		cd "$DS_HOME"
		for X in Backgrounds Body\ Data Bootstrap Catalogue Creature\ Galleries Genetics Images Journal My\ Agents My\ Creatures My\ Worlds Overlay\ Data Sounds Users; do
			mkdir -p "$X"
		done
	fi

	cd "$DS_HOME"

	# See if Creatures 3 is there
	if [ -d "$C3_MAIN" ]
	then
		echo "Creatures 3 found at $C3_MAIN"
		C3_INSTALLED=true
	else
		echo ""
		echo "Creatures 3 is not installed (you can buy it, or you can"
		echo "buy Creatures Internet Edition, which has Docking Station"
		echo "and the Magma Norns bundled with it, see the web site"
		echo "http://ds.creatures.net for more info)"
		echo ""
		C3_INSTALLED=
	fi
	# See if we need to update machine.cfg
	# (in case C3 has been installed or uninstalled)
	if [ -e "machine.cfg" ]
	then
		# Check if current config file refers to C3
		if ! grep "Everything Dummy" machine.cfg >/dev/null
		then
			if [ -z "$C3_INSTALLED" ]
			then
				echo "Creatures 3 has been removed since last launch"
				rm machine.cfg
			fi
		else
			if [ ! -z "$C3_INSTALLED" ]
			then
				echo "Creatures 3 has been installed since last launch"
				rm machine.cfg
			fi
		fi
	fi

	# Check for obsolete machine.cfg
	if [ -e "machine.cfg" ]
	then
		if ! grep "Main Auxiliary" machine.cfg >/dev/null
		then
			echo "Out of date machine.cfg - updating"
			rm machine.cfg
		fi
	fi

	# Create config file pointing to correct directories
	if [ ! -e "machine.cfg" ]; then
		echo "Pointing to directories"
		echo "\"Game Name\" \"Docking Station\"" > machine.cfg
		cat >>machine.cfg <<END
"Backgrounds Directory" "$DS_MAIN/Backgrounds/"
"Body Data Directory" "$DS_MAIN/Body Data/"
"Bootstrap Directory" "$DS_MAIN/Bootstrap/"
"Catalogue Directory" "$DS_MAIN/Catalogue/"
"Creature Database Directory" "$DS_MAIN/Creature Galleries/"
"Exported Creatures Directory" "$DS_MAIN/My Creatures/"
"Genetics Directory" "$DS_MAIN/Genetics/"
"Images Directory" "$DS_MAIN/Images/"
"Journal Directory" "$DS_MAIN/Journal/"
"Main Directory" "$DS_MAIN/"
"Overlay Data Directory" "$DS_MAIN/Overlay Data/"
"Resource Files Directory" "$DS_MAIN/My Agents/"
"Sounds Directory" "$DS_MAIN/Sounds/"
"Users Directory" "$DS_MAIN/Users/"
"Worlds Directory" "$DS_MAIN/My Worlds/"
END
		cat >>machine.cfg <<END
"Auxiliary 2 Backgrounds Directory" "$DS_HOME/Backgrounds/"
"Auxiliary 2 Body Data Directory" "$DS_HOME/Body Data/"
"Auxiliary 2 Bootstrap Directory" "$DS_HOME/Bootstrap/"
"Auxiliary 2 Catalogue Directory" "$DS_HOME/Catalogue/"
"Auxiliary 2 Creature Database Directory" "$DS_HOME/Creature Galleries/"
"Auxiliary 2 Exported Creatures Directory" "$DS_HOME/My Creatures/"
"Auxiliary 2 Genetics Directory" "$DS_HOME/Genetics/"
"Auxiliary 2 Images Directory" "$DS_HOME/Images/"
"Auxiliary 2 Journal Directory" "$DS_HOME/Journal/"
"Auxiliary 2 Main Directory" "$DS_HOME/"
"Auxiliary 2 Overlay Data Directory" "$DS_HOME/Overlay Data/"
"Auxiliary 2 Resource Files Directory" "$DS_HOME/My Agents/"
"Auxiliary 2 Sounds Directory" "$DS_HOME/Sounds/"
"Auxiliary 2 Users Directory" "$DS_HOME/Users/"
"Auxiliary 2 Worlds Directory" "$DS_HOME/My Worlds/"
"Main Auxiliary" 2
END
		if [ ! -z "$C3_INSTALLED" ]
		then
			echo "Creatures 3 is installed, connecting to it"
			cat >>machine.cfg <<END
"Auxiliary 1 Backgrounds Directory" "$C3_MAIN/Backgrounds/"
"Auxiliary 1 Body Data Directory" "$C3_MAIN/Body Data/"
"Auxiliary 1 Bootstrap Directory" "$C3_MAIN/Bootstrap/"
"Auxiliary 1 Catalogue Directory" "$C3_MAIN/Catalogue/"
"Auxiliary 1 Creature Database Directory" "$C3_MAIN/Creature Galleries/"
"Auxiliary 1 Exported Creatures Directory" "$C3_MAIN/My Creatures/"
"Auxiliary 1 Genetics Directory" "$C3_MAIN/Genetics/"
"Auxiliary 1 Images Directory" "$C3_MAIN/Images/"
"Auxiliary 1 Journal Directory" "$C3_MAIN/Journal/"
"Auxiliary 1 Main Directory" "$C3_MAIN/"
"Auxiliary 1 Overlay Data Directory" "$C3_MAIN/Overlay Data/"
"Auxiliary 1 Resource Files Directory" "$C3_MAIN/My Agents/"
"Auxiliary 1 Sounds Directory" "$C3_MAIN/Sounds/"
"Auxiliary 1 Users Directory" "$C3_MAIN/Users/"
"Auxiliary 1 Worlds Directory" "$C3_MAIN/My Worlds/"
END
		else
			echo "Creatures 3 is not installed"
			# To keep auxiliary directory numbers consistent,
			# we have to point Aux 1 to dummy paths when C3
			# isn't present. C3 _has_ to be Aux 1, as CAOS
			# code in the World Switcher refers to it as that.
			mkdir -p "Everything Dummy"
			cat >>machine.cfg <<END
"Auxiliary 1 Backgrounds Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Body Data Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Bootstrap Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Catalogue Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Creature Database Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Exported Creatures Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Genetics Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Images Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Journal Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Main Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Overlay Data Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Resource Files Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Sounds Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Users Directory" "$DS_HOME/Everything Dummy"
"Auxiliary 1 Worlds Directory" "$DS_HOME/Everything Dummy"
END
			fi
	fi

	# Language config file
	if [ ! -e "language.cfg" ]; then
		echo "Querying language"

		cd $DS_MAIN
		LANG=`$DS_MAIN/langpick`
		cd -
		if [ -z "$LANG" ]; then
			echo "Language cancelled"
			exit 0
		fi

		LANG_LIB=`cat <<LANGSET | grep $LANG.lang | cut --delimiter=" " --f=2
en.lang american
en-GB.lang english-uk
de.lang deu
fr.lang fra
nl.lang nld
it.lang ita
es.lang esp
LANGSET
`
		echo "Language $LANG" > language.cfg
		echo "LanguageCLibrary $LANG_LIB" >> language.cfg
	fi

	# User config file
	if [ ! -e "user.cfg" ]; then
		cat "$DS_MAIN/user.cfg" | tr -d "\r" | sed s/DS_/ds_/ > user.cfg
		echo "Icon \"$DS_MAIN/dstation.bmp\"" >> user.cfg
	fi

	# World switcher bootstrap needs to be in main directory
	if [ ! -e "$DS_HOME/Bootstrap/000 Switcher" ]; then
		ln -s "$DS_MAIN/Bootstrap/000 Switcher" $DS_HOME/Bootstrap
	fi
	if [ ! -e "$DS_HOME/lc2e-netbabel.so" ]; then
		ln -s "$DS_MAIN/lc2e-netbabel.so" $DS_HOME/lc2e-netbabel.so
	fi

	# Tell them to type "dockingstation" next time
	if echo "$SELF" | grep dstation-install >/dev/null
	then
		echo
		echo -n "You can type "
		echo -ne '\033]0;\w\007\033[32mdockingstation\033[0m'
		echo " to run the game from"
		echo "now on.  The original dstation-install file can be"
		echo "deleted, as dockingstation will also check for updates."
		echo
	fi

	# Launch the game
	echo "Welcome to Docking Station!"
	cd "$DS_HOME"
	export LD_LIBRARY_PATH="$DS_MAIN:$LD_LIBRARY_PATH"
	"$DS_MAIN"/lc2e --autokill
}

# Check command line parameteres
for PARAM in $@
do
	if [ "$PARAM" = "uninstall" ]
	then
		uninstall
		exit 0
	elif [ "$PARAM" = "lang" ]
	then
		echo "Forcing language selection for $USER"
		rm -f ~/.dockingstation/language.cfg
	elif [ "$PARAM" = "cleanse" ] 
	then
		echo "Forcing check of installed files"
		check_writeable "$INSTALL_DEST"
		echo > $INSTALL_DEST/$BUILD_FILE_GLOBAL
		echo > $INSTALL_DEST/$BUILD_FILE_PORT
	elif [ "$PARAM" = "nocheck" ]
	then
		NO_CHECK=true
	elif [ "$PARAM" = "nolaunch" ]
	then
		NO_LAUNCH=true
	elif [ "$PARAM" != "" ]
	then
		echo
		echo "Docking Station InstallBlast"
		echo "----------------------------"
		echo
		echo To download and run the game, simply run this script in an
		echo X terminal with no parameters.  You will be prompted for 
		echo the root password if necessary, so run the script as an
		echo ordinary user.
		echo 	
		echo When the download is complete the game will automatically
		echo launch.  Next time, type \'dockingstation\' to check for
		echo updates and launch the game.
		echo
		echo Parameters are:
		echo "  lang - Change the language that you play the game in"
		echo "  cleanse - Forces a rescan of files to fix broken builds"
		echo "  nocheck - Do not automatically check for game updates"
		echo "  nolaunch - Do not launch the game when finished"
		echo "  uninstall - Uninstalls the game"
		echo
		echo Environment variables are:
		echo "  INSTALL_DEST - Directory to install game in"
		echo "  BIN_DEST - Directory to install executable link in"
		echo "  C3_MAIN - Where Creatures 3 is (use if autodetect fails)"
		echo 
		echo Note: After setting INSTALL_DEST and BIN_DEST for the initial
		echo install you shouldn\'t need to set them again.  You should
		echo launch the game by typing \$BIN_DEST/dockingstation or putting
		echo \$BIN_DEST on the path and typing dockingstation.  The script
		echo will find INSTALL_DEST automatically.
		echo 
		echo "Have fun!"
		exit 1
	fi
done

[ -z "$NO_CHECK" ] && update
[ -z "$NO_LAUNCH" ] && user_launch

exit 0

