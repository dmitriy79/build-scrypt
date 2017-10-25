#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script builds Crypto++ library from sources.

CRYPTOPP_TAR=CRYPTOPP_5_6_5.tar.gz
CRYPTOPP_DIR=CRYPTOPP_5_6_5

# Avoid shellcheck.net warning
CURR_DIR="$PWD"

# Sets the number of make jobs if not set in environment
: "${MAKE_JOBS:=4}"

###############################################################################

if [[ -z $(command -v gzip 2>/dev/null) ]]; then
    echo "Some packages gzip. Please install gzip."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if [[ ! -f "$HOME/.cacert/digicert-root-ca.pem" ]]; then
    echo "Crypto++ requires several CA roots. Please run build-cacert.sh."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

LETS_ENCRYPT_ROOT="$HOME/.cacert/lets-encrypt-root-x3.pem"
DIGICERT_ROOT="$HOME/.cacert/digicert-root-ca.pem"

###############################################################################

# Get environment if needed. We can't export it because it includes arrays.
if [[ -z "$BUILD_OPTS" ]]; then
    source ./build-environ.sh
fi

# The password should die when this subshell goes out of scope
if [[ -z "$SUDO_PASSWORD" ]]; then
    source ./build-password.sh
fi

###############################################################################

echo
echo "********** Crypto++ **********"
echo

wget --ca-certificate="$DIGICERT_ROOT" "https://github.com/weidai11/cryptopp/archive/$CRYPTOPP_TAR" -O "$CRYPTOPP_TAR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download Crypto++"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -rf "$CRYPTOPP_DIR" &>/dev/null
gzip -d < "$CRYPTOPP_TAR" | tar xf -
mv "cryptopp-$CRYPTOPP_DIR" "$CRYPTOPP_DIR"
cd "$CRYPTOPP_DIR"

MAKE_FLAGS=("-j" "$MAKE_JOBS" "all")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to build Crypto++"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if ! ./cryptest.exe v
then
    echo "Failed to test Crypto++"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

# OK to uncomment, commented for expediency
# if ! ./cryptest.exe tv all
# then
#     echo "Failed to test Crypto++"
#     [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
# fi

MAKE_FLAGS=("distclean")
"$MAKE" "${MAKE_FLAGS[@]}"

# Add the data directory for install
MAKE_FLAGS=("-j" "$MAKE_JOBS" "all")
if ! CXXFLAGS="-DNDEBUG -g2 -O2 -DCRYPTOPP_DATA_DIR='\"$INSTALL_PREFIX/share/cryptopp/\"'" "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to rebuild Crypto++"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("install" "PREFIX=$INSTALL_PREFIX")
if [[ ! (-z "$SUDO_PASSWORD") ]]; then
    echo "$SUDO_PASSWORD" | sudo -S "$MAKE" "${MAKE_FLAGS[@]}"
else
    "$MAKE" "${MAKE_FLAGS[@]}"
fi

cd "$CURR_DIR"

###############################################################################

# Set to false to retain artifacts
if true; then

    ARTIFACTS=("$CRYPTOPP_TAR" "$CRYPTOPP_DIR")
    for artifact in "${ARTIFACTS[@]}"; do
        rm -rf "$artifact"
    done

    # ./build-cryptopp.sh 2>&1 | tee build-cryptopp.log
    if [[ -e build-cryptopp.log ]]; then
        rm -f build-cryptopp.log
    fi
fi

[[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0