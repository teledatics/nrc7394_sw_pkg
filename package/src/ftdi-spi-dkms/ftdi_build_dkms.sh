#!/bin/bash -x

# Copyright (c) 2023, Teledatics Incorporated <admin@teledatics.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Script to download Teledatics FTDI USB-SPI driver and build a kernel 
# module from source code and install it in the running system.

# TODO: fix debian files & directories permissions

# NOTE: modify the following variables for the proper values
MAINTAINER_NAME_EMAIL="Teledatics Incorporated <support@teledatics.com>"
DKMS_REPO_URL="https://github.com/teledatics/ftdi-spi-linux"
GPG_KEY=""
MODULE_NAME="spi-ft232h"

# Create working directoru
TEMP_DIR=$(mktemp -d)
if [ ! -d "$TEMP_DIR" ]; then
	exit 1;
fi

WORK_DIR=$TEMP_DIR/work
mkdir -p $WORK_DIR
# Clone the source repository
FTDI_SPI_SRC=$TEMP_DIR/ftdi-spi-linux
git clone --depth 1 $DKMS_REPO_URL $FTDI_SPI_SRC

# Copy source code
cp -f $FTDI_SPI_SRC/* $WORK_DIR/ 2>/dev/null

# Get version
MODULE_MAJOR=$(grep VERSION_MAJOR $FTDI_SPI_SRC/VERSION | sed s/VERSION_MAJOR=*.//)
MODULE_MINOR=$(grep VERSION_MINOR $FTDI_SPI_SRC/VERSION | sed s/VERSION_MINOR=*.//)
MODULE_VERSION="$MODULE_MAJOR.$MODULE_MINOR"

if [ -z "$MODULE_MAJOR" -a ! "$MODULE_MAJOR" ]; then
	exit 1;
fi

if [ -z "$MODULE_MINOR" -a ! "$MODULE_MINOR" ]; then
	exit 1;
fi

# Copy modprobe conf files
MISC_DIR="$TEMP_DIR/misc"
mkdir -p $MISC_DIR

cp $FTDI_SPI_SRC/blacklist-ftdi_sio.conf $MISC_DIR/
cp $FTDI_SPI_SRC/spi-ft232h.conf $MISC_DIR/

MODPROBE_FILES=$(ls $MISC_DIR/spi*.conf | grep "spi" | tail -n 1)

# Move to the working directory
CUR_DIR=$(pwd)
cd $WORK_DIR

# Create a dkms.conf file
cat << EOF > dkms.conf
MAKE[0]="make KERNEL_DIR=/usr/src/linux-headers-$(uname -r) modules"
CLEAN="make KERNEL_DIR=/usr/src/linux-headers-$(uname -r) clean"
PACKAGE_NAME="$MODULE_NAME"
PACKAGE_VERSION="$MODULE_VERSION"
BUILT_MODULE_NAME[0]="$MODULE_NAME"
DEST_MODULE_LOCATION[0]="/updates"
REMAKE_INITRD=yes
AUTOINSTALL=yes
EOF

# Create the Debian packages (both source and binary)
sudo dkms remove $MODULE_NAME/$MODULE_VERSION --all
sudo dkms add .
sudo dkms build -m $MODULE_NAME -v $MODULE_VERSION
# sudo dkms install -m $MODULE_NAME -v $MODULE_VERSION
sudo dkms mkdsc -m $MODULE_NAME -v $MODULE_VERSION --source-only
sudo dkms mkdeb -m $MODULE_NAME -v $MODULE_VERSION --source-only

cd $TEMP_DIR
rm -Rf $WORK_DIR
mkdir -p $WORK_DIR
MOD_DIR="$WORK_DIR/$MODULE_NAME-dkms-$MODULE_VERSION"

cd $WORK_DIR

sudo cp /var/lib/dkms/$MODULE_NAME/$MODULE_VERSION/dsc/$MODULE_NAME-dkms_$MODULE_VERSION.dsc $WORK_DIR
sudo cp /var/lib/dkms/$MODULE_NAME/$MODULE_VERSION/dsc/$MODULE_NAME-dkms_$MODULE_VERSION.tar.gz $WORK_DIR

sudo dpkg-source -x $MODULE_NAME-dkms_$MODULE_VERSION.dsc

chmod 0755 $MOD_DIR
cd $MOD_DIR

# move misc under mod-src-dir
# copy nrc7292_cspi.bin, nrc7292_bd.dat to misc, update install file with misc/<files> /lib/firmware
# copy nrc.conf to misc, update debian/install file with misc/<filenames> /etc/modprobe.d/
# setup debian files

# Fix Section: in control file
sed -i "s/Section: .*/Section: kernel/" $MOD_DIR/debian/control

# Add proper Maintainer: to control file
sed -i "s/Maintainer: .*/Maintainer: $MAINTAINER_NAME_EMAIL/" $MOD_DIR/debian/control

# Add modprobe files
mv $TEMP_DIR/misc $MOD_DIR

if [ ! -z "$MODPROBE_FILES" ]; then
cat > $MOD_DIR/debian/$MODULE_NAME-dkms.install <<EOF
misc/* etc/modprobe.d
EOF
fi

# modify rules file to include modprobe files
sed -i '/\tdh_installdirs/i \
\tdh_install' $MOD_DIR/debian/rules

# update copyright file
echo "Copyright (c) Teledatics Incorporated 2023" > $MOD_DIR/debian/$MODULE_NAME-dkms.copyright

# fix permissions
chmod -R 0644 $MOD_DIR/debian/*
chmod -R 0755 $MOD_DIR/debian/rules
chmod -R 0755 $MOD_DIR

# Build DKMS package
debuild -uc -us

echo -n "################## Package $MODULE_NAME-dkms-$MODULE_VERSION built"

# Sign the package
if [ ! -z "$GPG_KEY" ]; then
	dpkg-sig --sign builder -k $GPG_KEY ../$MODULE_NAME-dkms_$MODULE_VERSION*.deb 2>&1 > /dev/null
	echo -n " and signed"
fi

echo " successfully! ##################"

# Clean up
cp ../$MODULE_NAME-dkms_$MODULE_VERSION*.deb $CUR_DIR
# rm -rf $TEMP_DIR