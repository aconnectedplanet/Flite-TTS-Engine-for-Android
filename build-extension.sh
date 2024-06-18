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
rm -fr extension/code

rm -fr obj

# Compile the java source files to class files
mkdir -p obj
${JAVAC} \
	-d obj \
	-classpath "src" \
	-bootclasspath "${ANDROID_PLATFORM_JAR}" \
	src/edu/cmu/cs/speech/tts/flite/FliteTtsService.java \
	src/edu/cmu/cs/speech/tts/flite/NativeFliteTts.java \
	src/edu/cmu/cs/speech/tts/flite/Voice.java 

# Convert the java class files to a classes.dex file
mkdir -p extension/code/jvm-android

jar cf \
	"extension/code/jvm-android/FliteServiceTTS.jar" \
	-C "obj" \
	.

# ${D8} --min-api "${ANDROID_MIN_SDK_VERSION}" --lib "${ANDROID_PLATFORM_JAR}" --output bin/ obj/edu/cmu/cs/speech/tts/flite/FliteTtsService.class obj/edu/cmu/cs/speech/tts/flite/providers/*.class

# # Create the initial (unaligned) apk
# ${AAPT} package -f -m -F ${UNALIGNED_APK} -M AndroidManifest.xml -S res -I "${ANDROID_PLATFORM_JAR}" 

# # Add the classes.dex file - note that aapt uses relative filenames and this
# # must be in the root, so its necessary to cd into the bin folder
# cd bin
# ${AAPT} add ../${UNALIGNED_APK} classes.dex
# cd ..

mkdir -p extension/code/armv7-android
cp libs/armeabi-v7a/* extension/code/armv7-android
mkdir -p extension/code/arm64-android
cp libs/arm64-v8a/* extension/code/arm64-android
mkdir -p extension/code/x86_64-android
cp libs/x86_64/* extension/code/x86_64-android
mkdir -p extension/code/x86-android
cp libs/x86/* extension/code/x86-android
