#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script verifies most prerequisites and creates
# an environment for other scripts to execute in.

###############################################################################

# Can't apply the fixup reliably. Ancient Bash causes build scripts
# to die after setting the environment. TODO... figure it out.

# Fixup ancient Bash
# https://unix.stackexchange.com/q/468579/56041
#if [[ -z "$BASH_SOURCE" ]]; then
#    BASH_SOURCE="$0"
#fi

###############################################################################

# Prerequisites needed for nearly all packages

LETS_ENCRYPT_ROOT="$HOME/.cacert/lets-encrypt-root-x3.pem"
IDENTRUST_ROOT="$HOME/.cacert/identrust-root-x3.pem"

if [[ ! -f "$IDENTRUST_ROOT" ]]; then
    echo "Some packages require several CA roots. Please run setup-cacerts.sh."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if [[ -z $(command -v autoreconf 2>/dev/null) ]]; then
    echo "Some packages require Autotools. Please install autoconf, automake and libtool."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if [[ -z $(command -v gzip 2>/dev/null) ]]; then
    echo "Some packages require gzip. Please install gzip."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

###############################################################################

CURR_DIR=$(pwd)

# `gcc ... -o /dev/null` does not work on Solaris due to LD bug.
# `mktemp` is not available on AIX or Git Windows shell...
infile="in.$RANDOM$RANDOM.c"
outfile="out.$RANDOM$RANDOM"
echo 'int main(int argc, char* argv[]) {return 0;}' > "$infile"
echo "" >> "$infile"

function finish {
  cd "$CURR_DIR"
  rm -f "$infile"* 2>/dev/null
  rm -f "$outfile"* 2>/dev/null
}
trap finish EXIT

###############################################################################

# Autotools on Solaris has an implied requirement for GNU gear. Things fall apart without it.
# Also see https://blogs.oracle.com/partnertech/entry/preparing_for_the_upcoming_removal.
if [[ -d "/usr/gnu/bin" ]]; then
    if [[ ! ("$PATH" == *"/usr/gnu/bin"*) ]]; then
        echo
        echo "Adding /usr/gnu/bin to PATH for Solaris"
        PATH="/usr/gnu/bin:$PATH"
    fi
elif [[ -d "/usr/swf/bin" ]]; then
    if [[ ! ("$PATH" == *"/usr/sfw/bin"*) ]]; then
        echo
        echo "Adding /usr/sfw/bin to PATH for Solaris"
        PATH="/usr/sfw/bin:$PATH"
    fi
elif [[ -d "/usr/ucb/bin" ]]; then
    if [[ ! ("$PATH" == *"/usr/ucb/bin"*) ]]; then
        echo
        echo "Adding /usr/ucb/bin to PATH for Solaris"
        PATH="/usr/ucb/bin:$PATH"
    fi
fi

###############################################################################

# Wget is special. We have to be able to bootstrap it and
# use the latest version throughout these scripts

if [[ -z "$WGET" ]]; then
    if [[ -e "$HOME/bootstrap/bin/wget" ]]; then
        WGET="$HOME/bootstrap/bin/wget"
    elif [[ -e "/usr/local/bin/wget" ]]; then
        WGET="/usr/local/bin/wget"
    else
        WGET=wget
    fi
fi

###############################################################################

THIS_SYSTEM=$(uname -s 2>&1)
IS_SOLARIS=$(echo -n "$THIS_SYSTEM" | grep -i -c 'sunos')
IS_DARWIN=$(echo -n "$THIS_SYSTEM" | grep -i -c 'darwin')
IS_AIX=$(echo -n "$THIS_SYSTEM" | grep -i -c 'aix')
IS_CYGWIN=$(echo -n "$THIS_SYSTEM" | grep -i -c 'cygwin')
IS_OPENBSD=$(echo -n "$THIS_SYSTEM" | grep -i -c 'openbsd')
IS_FREEBSD=$(echo -n "$THIS_SYSTEM" | grep -i -c 'freebsd')
IS_NETBSD=$(echo -n "$THIS_SYSTEM" | grep -i -c 'netbsd')
IS_BSD=$(echo -n "$THIS_SYSTEM" | grep -i -c -E 'freebsd|netbsd|openbsd')

THIS_MACHINE=$(uname -m 2>&1)
IS_IA32=$(echo -n "$THIS_MACHINE" | grep -E -i -c 'i86pc|i.86|amd64|x86_64')
IS_X86_64=$(echo -n "$THIS_MACHINE" | grep -E -i -c 'amd64|x86_64')
IS_MIPS=$(echo -n "$THIS_MACHINE" | grep -E -i -c 'mips')

# The BSDs and Solaris should have GMake installed if its needed
if [[ -z "$MAKE" ]]; then
    if [[ $(command -v gmake 2>/dev/null) ]]; then
        MAKE="gmake"
    else
        MAKE="make"
    fi
fi

# Needed for OpenSSL and make jobs
IS_GMAKE=$($MAKE -v 2>&1 | grep -i -c 'gnu make')

# If CC and CXX is not set, then use default or assume GCC
if [[ (-z "$CC" && $(command -v cc 2>/dev/null) ) ]]; then CC=$(command -v cc); fi
if [[ (-z "$CC" && $(command -v gcc 2>/dev/null) ) ]]; then CC=$(command -v gcc); fi
if [[ (-z "$CXX" && $(command -v CC 2>/dev/null) ) ]]; then CXX=$(command -v CC); fi
if [[ (-z "$CXX" && $(command -v g++ 2>/dev/null) ) ]]; then CXX=$(command -v g++); fi

IS_GCC=$("$CC" --version 2>&1 | grep -i -c -E 'gcc')
IS_CLANG=$("$CC" --version 2>&1 | grep -i -c -E 'clang|llvm')

###############################################################################

# Try to determine 32 vs 64-bit, /usr/local/lib, /usr/local/lib32,
# /usr/local/lib64 and /usr/local/lib/64. We drive a test compile
# using the supplied compiler and flags.
if $CC $CFLAGS bootstrap/bitness.c -o /dev/null &>/dev/null; then
    IS_64BIT=1
    IS_32BIT=0
    INSTX_BITNESS=64
else
    IS_64BIT=0
    IS_32BIT=1
    INSTX_BITNESS=32
fi

# Don't override a user choice of INSTX_PREFIX
if [[ -z "$INSTX_PREFIX" ]]; then
    INSTX_PREFIX="/usr/local"
fi

# Don't override a user choice of INSTX_LIBDIR
if [[ -z "$INSTX_LIBDIR" ]]; then
    if [[ "$IS_64BIT" -ne "0" ]]; then
        if [[ "$IS_SOLARIS" -ne "0" ]]; then
            INSTX_LIBDIR="$INSTX_PREFIX/lib/64"
        elif [[ (-d /usr/lib) && (-d /usr/lib32) ]]; then
            INSTX_LIBDIR="$INSTX_PREFIX/lib"
        elif [[ (-d /usr/lib) && (-d /usr/lib64) ]]; then
            INSTX_LIBDIR="$INSTX_PREFIX/lib64"
        else
            INSTX_LIBDIR="$INSTX_PREFIX/lib"
        fi
    else
        INSTX_LIBDIR="$INSTX_PREFIX/lib"
    fi
fi

# Solaris Fixup
if [[ "$IS_IA32" -eq 1 ]] && [[ "$INSTX_BITNESS" -eq 64 ]]; then
    IS_X86_64=1
fi

###############################################################################

PIC_ERROR=$($CC -fPIC -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
if [[ "$PIC_ERROR" -eq "0" ]]; then
    SH_PIC="-fPIC"
fi

# For the benefit of the programs and libraries. Make them run faster.
NATIVE_ERROR=$($CC -march=native -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
if [[ "$NATIVE_ERROR" -eq "0" ]]; then
    SH_NATIVE="-march=native"
fi

RPATH_ERROR=$($CC -Wl,-rpath,$INSTX_LIBDIR -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
if [[ "$RPATH_ERROR" -eq "0" ]]; then
    SH_RPATH="-Wl,-rpath,$INSTX_LIBDIR"
fi

# AIX ld uses -R for runpath when -bsvr4
RPATH_ERROR=$($CC -Wl,-R,$INSTX_LIBDIR -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
if [[ "$RPATH_ERROR" -eq "0" ]]; then
    SH_RPATH="-Wl,-R,$INSTX_LIBDIR"
fi

OPENMP_ERROR=$($CC -fopenmp -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
if [[ "$SH_ERROR" -eq "0" ]]; then
    SH_OPENMP="-fopenmp"
fi

SH_ERROR=$($CC -Wl,--enable-new-dtags -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
if [[ "$SH_ERROR" -eq "0" ]]; then
    SH_DTAGS="-Wl,--enable-new-dtags"
fi

# OS X linker and install names
SH_ERROR=$($CC -headerpad_max_install_names -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
if [[ "$SH_ERROR" -eq "0" ]]; then
    SH_INSTNAME="-headerpad_max_install_names"
fi

# Debug symbols
if [[ -z "$SH_SYM" ]]; then
    SH_ERROR=$($CC -g2 -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
    if [[ "$SH_ERROR" -eq "0" ]]; then
        SH_SYM="-g2"
    else
        SH_ERROR=$($CC -g -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
        if [[ "$SH_ERROR" -eq "0" ]]; then
            SH_SYM="-g"
        fi
    fi
fi

# Optimizations symbols
if [[ -z "$SH_OPT" ]]; then
    SH_ERROR=$($CC -O2 -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
    if [[ "$SH_ERROR" -eq "0" ]]; then
        SH_OPT="-O2"
    else
        SH_ERROR=$($CC -O -o "$outfile" "$infile" 2>&1 | tr ' ' '\n' | wc -l)
        if [[ "$SH_ERROR" -eq "0" ]]; then
            SH_OPT="-O"
        fi
    fi
fi

# OpenBSD does not have -ldl
if [[ -z "$SH_DL" ]]; then
    SH_ERROR=$($CC -o "$outfile" "$infile" -ldl 2>&1 | tr ' ' '\n' | wc -l)
    if [[ "$SH_ERROR" -eq "0" ]]; then
        SH_DL="-ldl"
    fi
fi

if [[ -z "$SH_PTHREAD" ]]; then
    SH_ERROR=$($CC -o "$outfile" "$infile" -lpthread 2>&1 | tr ' ' '\n' | wc -l)
    if [[ "$SH_ERROR" -eq "0" ]]; then
        SH_PTHREAD="-lpthread"
    fi
fi

###############################################################################

# CA cert path? Also see http://gagravarr.org/writing/openssl-certs/others.shtml
# For simplicity use $INSTX_PREFIX/etc/pki. Avoid about 10 different places.

SH_CACERT_PATH="$INSTX_PREFIX/etc/pki"
SH_CACERT_FILE="$INSTX_PREFIX/etc/pki/cacert.pem"

###############################################################################

BUILD_PKGCONFIG=("$INSTX_LIBDIR/pkgconfig")
BUILD_CPPFLAGS=("-I$INSTX_PREFIX/include" "-DNDEBUG")
BUILD_CFLAGS=("$SH_SYM" "$SH_OPT")
BUILD_CXXFLAGS=("$SH_SYM" "$SH_OPT")
BUILD_LDFLAGS=("-L$INSTX_LIBDIR")
BUILD_LIBS=()

if [[ ! -z "$SH_NATIVE" ]]; then
    BUILD_CFLAGS[${#BUILD_CFLAGS[@]}]="$SH_NATIVE"
    BUILD_CXXFLAGS[${#BUILD_CXXFLAGS[@]}]="$SH_NATIVE"
fi

if [[ ! -z "$SH_PIC" ]]; then
    BUILD_CFLAGS[${#BUILD_CFLAGS[@]}]="$SH_PIC"
    BUILD_CXXFLAGS[${#BUILD_CXXFLAGS[@]}]="$SH_PIC"
fi

if [[ ! -z "$SH_RPATH" ]]; then
    BUILD_LDFLAGS[${#BUILD_LDFLAGS[@]}]="$SH_RPATH"
fi

if [[ ! -z "$SH_DTAGS" ]]; then
    BUILD_LDFLAGS[${#BUILD_LDFLAGS[@]}]="$SH_DTAGS"
fi

if [[ ! -z "$SH_DL" ]]; then
    BUILD_LIBS[${#BUILD_LIBS[@]}]="$SH_DL"
fi

if [[ ! -z "$SH_PTHREAD" ]]; then
    #BUILD_LIBS+=("$SH_PTHREAD")
    BUILD_LIBS[${#BUILD_LIBS[@]}]="$SH_PTHREAD"
fi

#if [[ "$IS_DARWIN" -ne "0" ]] && [[ ! -z "$SH_INSTNAME" ]]; then
#    BUILD_LDFLAGS+=("$SH_INSTNAME")
#    BUILD_LDFLAGS[${#BUILD_LDFLAGS[@]}]="$SH_INSTNAME"
#fi

# Used to track packages that have been built by these scripts.
# The accounting is local to a user account. There is no harm
# in rebuilding a package under another account.
if [[ -z "$INSTX_CACHE" ]]; then
    INSTX_CACHE="$HOME/.build-scripts"
    mkdir -p "$INSTX_CACHE"
fi

###############################################################################

# If the package is older than 7 days, then rebuild it. This sidesteps the
# problem of continually rebuilding the same package when installing a
# program like Git and SSH. It also avoids version tracking by automatically
# building a package after 7 days (even if it is the same version).
for pkg in $(find "$INSTX_CACHE" -type f -mtime +7 2>/dev/null);
do
    # echo "Setting $pkg for rebuild"
    rm -f "$pkg" 2>/dev/null
done

###############################################################################

# Print a summary once
if [[ -z "$PRINT_ONCE" ]]; then

    echo ""
    echo "Common flags and options:"
    echo ""
    echo " INSTX_BITNESS: $INSTX_BITNESS-bits"
    echo "  INSTX_PREFIX: $INSTX_PREFIX"
    echo "  INSTX_LIBDIR: $INSTX_LIBDIR"

    echo ""
    echo "  PKGCONFPATH: ${BUILD_PKGCONFIG[*]}"
    echo "     CPPFLAGS: ${BUILD_CPPFLAGS[*]}"
    echo "       CFLAGS: ${BUILD_CFLAGS[*]}"
    echo "     CXXFLAGS: ${BUILD_CXXFLAGS[*]}"
    echo "      LDFLAGS: ${BUILD_LDFLAGS[*]}"
    echo "       LDLIBS: ${BUILD_LIBS[*]}"
    echo ""

    echo " WGET: $WGET"
    if [[ ! -z "$SH_CACERT_PATH" ]]; then
        echo " SH_CACERT_PATH: $SH_CACERT_PATH"
    fi
    if [[ ! -z "$SH_CACERT_FILE" ]]; then
        echo " SH_CACERT_FILE: $SH_CACERT_FILE"
    fi

    export PRINT_ONCE="TRUE"
fi

[[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0
