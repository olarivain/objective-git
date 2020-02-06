#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/xcode_functions.sh"

function setup_build_environment ()
{
    # augment path to help it find cmake installed in /usr/local/bin,
    # e.g. via brew. Xcode's Run Script phase doesn't seem to honor
    # ~/.MacOSX/environment.plist
    PATH="/usr/local/bin:/opt/boxen/homebrew/bin:$PATH"

    pushd "$SCRIPT_DIR/.." > /dev/null
    ROOT_PATH="$PWD"
    popd > /dev/null

    CLANG="/usr/bin/xcrun clang"
    CC="${CLANG}"
    CPP="${CLANG} -E"

    # We need to clear this so that cmake doesn't have a conniption
    MACOSX_DEPLOYMENT_TARGET=""

    XCODE_MAJOR_VERSION=$(xcode_major_version)

    CAN_BUILD_64BIT="0"

    # If IPHONEOS_DEPLOYMENT_TARGET has not been specified
    # setup reasonable defaults to allow running of a build script
    # directly (ie not from an Xcode proj)
    if [ -z "${IPHONEOS_DEPLOYMENT_TARGET}" ]
    then
        IPHONEOS_DEPLOYMENT_TARGET="6.0"
    fi

    # Determine if we can be building 64-bit binaries
    if [ "${XCODE_MAJOR_VERSION}" -ge "5" ] && [ $(echo ${IPHONEOS_DEPLOYMENT_TARGET} '>=' 6.0 | bc -l) == "1" ]
    then
        CAN_BUILD_64BIT="1"
    fi

    ARCHS="i386 armv7 armv7s"
    if [ "${CAN_BUILD_64BIT}" -eq "1" ]
    then
        # For some stupid reason cmake needs simulator
        # builds to be first
        ARCHS="x86_64 ${ARCHS} arm64 x86_64-apple-darwin"
    fi

    # Setup a shared area for our build artifacts
    INSTALL_PATH="${ROOT_PATH}/External/build"
    mkdir -p "${INSTALL_PATH}"
    mkdir -p "${INSTALL_PATH}/log"
    mkdir -p "${INSTALL_PATH}/include"
    mkdir -p "${INSTALL_PATH}/lib/pkgconfig"
}

function build_all_archs ()
{
    setup_build_environment

    local setup=$1
    local build_arch=$2
    local finish_build=$3

    # run the prepare function
    eval $setup

    echo "Building for ${ARCHS}"

    for IN_ARCH in ${ARCHS}
    do
        echo "in arch ${IN_ARCH}"
        if [ "${IN_ARCH}" == "i386" ] || [ "${IN_ARCH}" == "x86_64" ]
        then
            ARCH=${IN_ARCH}
            PLATFORM="iphonesimulator"
            NOT_HOST=$PLATFORM
        elif [ "${IN_ARCH}" == "x86_64-apple-darwin" ]
        then

            ARCH="x86_64"
            PLATFORM="maccatalyst"
            NOT_HOST="macos"
        else
            ARCH=${IN_ARCH}
            PLATFORM="iphoneos"
            NOT_HOST=$PLATFORM
        fi

        if [ "${IN_ARCH}" == "x86_64-apple-darwin" ]
        then
            SDKVERSION="10.15"
        else
            SDKVERSION=$(ios_sdk_version)
        fi

        if [ "${ARCH}" == "arm64" ]
        then
            HOST="aarch64-apple-darwin"
        else
            HOST="${ARCH}-apple-darwin"
        fi

        SDKNAME="${NOT_HOST}${SDKVERSION}"
        if [ "${IN_ARCH}" == "x86_64-apple-darwin" ]
         then
            SDKROOT="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.15.sdk"
        else
            SDKROOT="$(ios_sdk_path ${SDKNAME})"
        fi
        
        echo "SDK IS ${NOT_HOST}, ${SDKNAME}, ${SDKROOT}."

        LOG="${INSTALL_PATH}/log/${LIBRARY_NAME}-${ARCH}.log"
        [ -f "${LOG}" ] && rm "${LOG}"

        echo "Building ${LIBRARY_NAME} for ${SDKNAME} ${ARCH}"
        echo "Build log can be found in ${LOG}"
        echo "The arch is ${ARCH}"
        echo "Please stand by..."

        ARCH_INSTALL_PATH="${INSTALL_PATH}/${SDKNAME}-${ARCH}.sdk"
        mkdir -p "${ARCH_INSTALL_PATH}"

        # run the per arch build command
        eval $build_arch
    done

    # finish the build (usually lipo)
    eval $finish_build
}

