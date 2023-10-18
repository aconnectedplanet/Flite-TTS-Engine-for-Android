#!/bin/sh
FLITE_APP_DIR="$(dirname $(readlink -f "$0"))"
FLITE_BUILD_DIR="${FLITE_APP_DIR}/flite"

ANDROID_BUILD_TOOLS=31.0.0
ANDROID_NDK_VERSION=r23c
ANDROID_NDK_PLATFORM_VERSION=21
ANDROID_API_VERSION=33
ANDROID_MIN_SDK_VERSION=23

ANDROID_PLATFORM_JAR="${ANDROID_SDK}/platforms/android-${ANDROID_API_VERSION}/android.jar"

AAPT="${ANDROID_SDK}/build-tools/${ANDROID_BUILD_TOOLS}/aapt"
D8="${ANDROID_SDK}/build-tools/${ANDROID_BUILD_TOOLS}/d8"
APKSIGNER="${ANDROID_SDK}/build-tools/${ANDROID_BUILD_TOOLS}/apksigner"
ZIPALIGN="${ANDROID_SDK}/build-tools/${ANDROID_BUILD_TOOLS}/zipalign"
JAVAC=javac
NDK_BUILD="${ANDROID_NDK}/ndk-build"

UNALIGNED_APK=bin/FliteEngine.unaligned.apk
ALIGNED_APK=bin/FliteEngine.apk

# Abort after first error
set -e
OLDPWD="${PWD}"

# Check for required environment vairables
HAVE_REQUIRED_ENVS=true

if [ -z "${ANDROID_NDK}" ] && [ -z "${ANDROID_NDK_HOME}" ];
then
	echo "Missing Android NDK path environment variable: ANDROID_NDK / ANDROID_NDK_HOME" >&2
	HAVE_REQUIRED_ENVS=false
fi

if [ -z "${ANDROID_SDK}" ] && [ -z "${ANDROID_HOME}" ];
then
	echo "Missing Android SDK path environment variable: ANDROID_SDK / ANDROID_HOME" >&2
	HAVE_REQUIRED_ENVS=false
fi

if ! ${HAVE_REQUIRED_ENVS};
then
	exit 1
fi

export FLIGHT_APP_DIR

export FLITEDIR=${FLITE_BUILD_DIR}

# Build the `flite` engine for all supported targets
cd "${FLITEDIR}"
for arch in armeabiv7a aarch64 x86 x86_64;
do
	if ! [ -e "${FLITEDIR}/build/${arch}-android/lib/libflite.a" ];
	then
		./configure --with-langvox=android --target="${arch}-android"
		make -j4
	fi
done
cd "${OLDPWD}"

# Build the jni library - this uses the jni/*.mk files
"${NDK_BUILD}" V=1

# Remove any previously generated files related to the app
rm -f ${UNALIGNED_APK}
rm -f ${ALIGNED_APK}
rm -f bin/classes.dex

# Package and process the apps resources and assets
${AAPT} package -f -m -J src -M AndroidManifest.xml -S res -I "${ANDROID_PLATFORM_JAR}"

# Compile the java source files to class files
mkdir -p obj
${JAVAC} -d obj -classpath "src" -bootclasspath "${ANDROID_PLATFORM_JAR}" src/edu/cmu/cs/speech/tts/flite/*.java src/edu/cmu/cs/speech/tts/flite/providers/*.java

# Convert the java class files to a classes.dex file
mkdir -p bin
${D8} --min-api "${ANDROID_MIN_SDK_VERSION}" --lib "${ANDROID_PLATFORM_JAR}" --output bin/ obj/edu/cmu/cs/speech/tts/flite/*.class obj/edu/cmu/cs/speech/tts/flite/providers/*.class

# Create the initial (unaligned) apk
${AAPT} package -f -m -F ${UNALIGNED_APK} -M AndroidManifest.xml -S res -I "${ANDROID_PLATFORM_JAR}" 

# Add the classes.dex file - note that aapt uses relative filenames and this
# must be in the root, so its necessary to cd into the bin folder
cd bin
${AAPT} add ../${UNALIGNED_APK} classes.dex
cd ..

# The ndk-build command generates the binaries in libs, but apks must have them
# in lib, so temporarily rename the folder and then add using aapt.
mv libs lib
${AAPT} add ${UNALIGNED_APK} lib/armeabi-v7a/*
${AAPT} add ${UNALIGNED_APK} lib/arm64-v8a/*
${AAPT} add ${UNALIGNED_APK} lib/x86_64/*
${AAPT} add ${UNALIGNED_APK} lib/x86/*
mv lib libs

# Remove any existing debug keystore, and generate a new debug keystore
rm -f bin/debug.keystore
keytool -genkey -v -keystore bin/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"

# Generate an aligned apk from the unaligned apk
${ZIPALIGN} -f 4 ${UNALIGNED_APK} ${ALIGNED_APK}

# Sign the apk
${APKSIGNER} sign --ks bin/debug.keystore --ks-pass pass:android --key-pass pass:android ${ALIGNED_APK}
