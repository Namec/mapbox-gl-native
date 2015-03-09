#!/usr/bin/env bash

set -e
set -o pipefail

BUILDTYPE=${BUILDTYPE:-Release}
TESTMUNK=${TESTMUNK:-no}
case `uname -s` in
    'Darwin') JOBS=$((`sysctl -n hw.ncpu` + 2)) ;;
    'Linux')  JOBS=$((`nproc` + 2)) ;;
    *)        JOBS=1 ;;
esac

source ./scripts/travis_helper.sh

# Add Mason to PATH
export PATH="`pwd`/.mason:${PATH}"
export MASON_DIR="`pwd`/.mason"

export MASON_PLATFORM=android
export MASON_ANDROID_ABI=${ANDROID_ABI:-arm-v7}
export ANDROID_HOME=`pwd`/android/sdk
export PATH="`pwd`/android/sdk/tools:${PATH}"

echo \$ ./scripts/android/toolchain.sh
./scripts/android/toolchain.sh

mapbox_time "checkout_styles" \
git submodule update --init styles

mkdir -p ./android/java/MapboxGLAndroidSDKTestApp/src/main/res/raw
echo "${MAPBOX_ACCESS_TOKEN}" > ./android/java/MapboxGLAndroidSDKTestApp/src/main/res/raw/token.txt

mapbox_time "compile_program" \
make android -j${JOBS} BUILDTYPE=${BUILDTYPE}

if [ ! -z "${AWS_ACCESS_KEY_ID}" ] && [ ! -z "${AWS_SECRET_ACCESS_KEY}" ] ; then
    # Add awscli to PATH for uploading the results
    export PATH="`python -m site --user-base`/bin:${PATH}"

    mapbox_time_start "deploy_results"
    echo "Deploying results..."
    aws s3 cp ./android/java/MapboxGLAndroidSDKTestApp/build/outputs/apk/MapboxGLAndroidSDKTestApp-debug.apk s3://mapbox/mapbox-gl-native/android/build/${TRAVIS_JOB_NUMBER}/MapboxGLAndroidSDKTestApp-debug.apk
    aws s3 cp ./android/java/MapboxGLAndroidSDKTestApp/build/outputs/apk/MapboxGLAndroidSDKTestApp-release-unsigned.apk s3://mapbox/mapbox-gl-native/android/build/${TRAVIS_JOB_NUMBER}/MapboxGLAndroidSDKTestApp-release-unsigned.apk
    mapbox_time_finish
fi
