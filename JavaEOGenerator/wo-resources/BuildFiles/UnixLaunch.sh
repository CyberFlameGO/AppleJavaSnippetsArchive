#!/bin/sh

export PATH
PATH=/usr/xpg4/bin:${PATH}:/bin:/usr/bin

#
# Declare variables.
#
export APPLICATION_CLASS
export CLASSPATH_FILE
export CLASSPATH_FILENAME
export COMMAND_LINE_ARGS
export CURRDIR
export DEBUG_MODE
export DEFAULT_JVM_OPTIONS
export JAVA_EXECUTABLE
export JAVA_EXECUTABLE_ARGS
export JDB_EXECUTABLE
export JDB_OPTIONS
export JVM_EXECUTABLE
export JVM_OPTIONS
export LOCALROOT
export PLATFORM_DESCRIPTOR
export PLATFORM_NAME
export PLATFORM_TYPE
export RELATIVE_WOADIR
export SCRIPT_NAME
export WOA_CONTENTS_DIR
export WOA_TOP_LEVEL
export WOROOT

#
# Declare functions.
#
readHeaderValue() {
    value="`awk '{print}' RS='\r*\n' < \"$3\" | sed -e \"/^# *$2 *==*/!d\" -e \"s/^\(# *$2 *==* *\)//\"`";
    rhvCmd="$1=\${value}";
    eval ${rhvCmd};
    return;
}

#
# Initialize variables.
#
CURRDIR="`pwd`"
SCRIPT_NAME="`basename \"$0\" .sh`"

#
# Compute WOA_CONTENTS_DIR as the absolute path to the Contents directory beneath
# top-level directory of the .woa.
# Our working directory is the top-level directory of the woa bundle, so cd to
# there.
#
RELATIVE_WOADIR="`dirname \"$0\"`"
WOA_TOP_LEVEL="`cd \"${RELATIVE_WOADIR}\"; pwd | sed -e 's%\/Contents.*$%%'`"
WOA_CONTENTS_DIR="${WOA_TOP_LEVEL}/Contents"

#
# We need to be in the .woa when we invoke the JVM (so that the "user.dir"
# Java system property is equal to the path to the .woa).
#
cd "${WOA_TOP_LEVEL}"

#
# Configure the launch environment based on the platform information.
#
# Expected uname values:
#   Darwin
#   Mac OS
#   Rhapsody  (this is for things like JavaConverter, which need to run on
#              Mac OS X Server 1.2)
#   *Windows* (this prints out an error message)
#   *winnt*   (ditto)
#
# Everything else is treated as "UNIX", the default.
#
PLATFORM_NAME="`uname -s`"

if [ "${PLATFORM_NAME}" = "" ]
then
    echo ${SCRIPT_NAME}: Unable to access \"uname\" executable!  Terminating. 1>&2
    echo If running on Windows, use \"$0.cmd\" to launch your application! 1>&2
    exit 1
fi

case "${PLATFORM_NAME}" in
    "Darwin")   PLATFORM_DESCRIPTOR=MacOS
                PLATFORM_TYPE=Darwin
                ;;
    "Mac OS")   PLATFORM_DESCRIPTOR=MacOS
                PLATFORM_TYPE=Darwin
                ;;
    "Rhapsody") PLATFORM_DESCRIPTOR=MacOS
                PLATFORM_TYPE=Rhapsody
                ;;
    *Windows*)  echo Use \"$0.cmd\" to launch your application!  Terminating. 1>&2
                exit 1
                ;;
    *winnt*)    echo Use \"$0.cmd\" to launch your application!  Terminating. 1>&2
                exit 1
                ;;
    *)          PLATFORM_DESCRIPTOR=UNIX
                PLATFORM_TYPE=Other
                ;;
esac

#
# Depending upon the platform, provide default values for the path
# abstractions (we call these values "shorthands").
#
if [ "${PLATFORM_TYPE}" = "Rhapsody" ]
then
    LOCALROOT=/Local
    WOROOT=/System
elif [ "$PLATFORM_TYPE" = "Darwin" ]
then
    LOCALROOT=
    WOROOT=/System
else
    WOROOT=${NEXT_ROOT}
    LOCALROOT=${NEXT_ROOT}/Local
fi

#
# Read the appropriate classpath file, perform path interpolations, and
# configure the launch variables using values present in the classpath file
# comment header.
# The octothorpe symbol is used to "comment out" classpath entries in the
# classpath file.  It's also used to create a header in the classpath file
# that contains launch variable values.
#
CLASSPATH_FILENAME=${PLATFORM_DESCRIPTOR}ClassPath.txt
CLASSPATH_FILE=${WOA_CONTENTS_DIR}/${PLATFORM_DESCRIPTOR}/${CLASSPATH_FILENAME}

if [ "${PLATFORM_TYPE}" = "Other" ]
then
    if [ "${NEXT_ROOT}" = "" ]
    then
        echo ${SCRIPT_NAME}: NEXT_ROOT environment variable is not set! 1>&2
    fi
fi

echo Reading ${CLASSPATH_FILENAME} ...

if [ -f "${CLASSPATH_FILE}" -a -r "${CLASSPATH_FILE}" ]
then
    readHeaderValue APPLICATION_CLASS ApplicationClass "${CLASSPATH_FILE}"
    readHeaderValue JDB_EXECUTABLE    JDB              "${CLASSPATH_FILE}"
    readHeaderValue JDB_OPTIONS       JDBOptions       "${CLASSPATH_FILE}"
    readHeaderValue JVM_EXECUTABLE    JVM              "${CLASSPATH_FILE}"
    readHeaderValue JVM_OPTIONS       JVMOptions       "${CLASSPATH_FILE}"

    # Just in case, provide some default values as a last resort.
    if [ "${APPLICATION_CLASS}" = "" ]
    then
        echo ${SCRIPT_NAME}: WARNING -- Using default value, because ApplicationClass header is missing from \"${CLASSPATH_FILE}\"! 1>&2
        APPLICATION_CLASS=Application
    fi
    if [ "${JDB_EXECUTABLE}" = "" ]
    then
        echo ${SCRIPT_NAME}: WARNING -- Using default value, because JDB header is missing from \"${CLASSPATH_FILE}\"! 1>&2
        JDB_EXECUTABLE=jdb
    fi
    if [ "${JVM_EXECUTABLE}" = "" ]
    then
        echo ${SCRIPT_NAME}: WARNING -- Using default value, because JVM header is missing from \"${CLASSPATH_FILE}\"! 1>&2
        JVM_EXECUTABLE=java
    fi
else
    echo ${SCRIPT_NAME}: Unable to read \"${CLASSPATH_FILE}\"!  Terminating. 1>&2
    exit 1
fi

#
# Define some arguments that we always want to pass to the JVM.  These can be
# overridden in the classpath file using the JVMOptions or JDBOptions header or
# on the command line.
#
DEFAULT_JVM_OPTIONS="-DWORootDirectory=\"${WOROOT}\" -DWOLocalRootDirectory=\"${LOCALROOT}\" -DWOUserDirectory=\"${CURRDIR}\" -DWOEnvClassPath=\"${CLASSPATH}\" -DWOApplicationClass=${APPLICATION_CLASS} -DWOPlatform=${PLATFORM_DESCRIPTOR} -Dcom.webobjects.pid=$$"

#
# Set the default JVM performance parameters on Mac OS X.  These can be
# overridden in the classpath file using the JVMOptions or JDBOptions header or
# on the command line.
#
if [ "${PLATFORM_TYPE}" = "Darwin" ]
then
    # Initial heap size is 32M
    DEFAULT_JVM_OPTIONS="-Xms32m${DEFAULT_JVM_OPTIONS:+ $DEFAULT_JVM_OPTIONS}"
    # Maximum heap size is 64M
    DEFAULT_JVM_OPTIONS="-Xmx64m${DEFAULT_JVM_OPTIONS:+ $DEFAULT_JVM_OPTIONS}"
    # Default size of new generation is 2M
    DEFAULT_JVM_OPTIONS="-XX:NewSize=2m${DEFAULT_JVM_OPTIONS:+ $DEFAULT_JVM_OPTIONS}"
fi

#
# Configure the executable to use based on whether the app is to be launched
# for debugging.
# Also append the arguments from the classpath file to the JVM argument list
# based on this criterion.
#
DEBUG_MODE=false

if [ "`echo $* | grep -e '-NSPBDebug' -e '-NSJavaDebugging *YES'`" != "" ]
then
    DEBUG_MODE=true
    JAVA_EXECUTABLE=${JDB_EXECUTABLE}
elif [ "`echo ${_JAVA_OPTIONS} | grep -e '-Xrunjdwp'`" != "" ]
then
    DEBUG_MODE=true
    JAVA_EXECUTABLE=${JVM_EXECUTABLE}
fi

if [ "${DEBUG_MODE}" = "true" ]
then
    JAVA_EXECUTABLE_ARGS="${DEFAULT_JVM_OPTIONS:+$DEFAULT_JVM_OPTIONS }${JVM_OPTIONS:+$JVM_OPTIONS }${JDB_OPTIONS:+$JDB_OPTIONS }"
else
    JAVA_EXECUTABLE=${JVM_EXECUTABLE}
    JAVA_EXECUTABLE_ARGS="${DEFAULT_JVM_OPTIONS:+$DEFAULT_JVM_OPTIONS }${JVM_OPTIONS:+$JVM_OPTIONS }"
fi

#
# All -D flags need to be passed to the JVM before the application class is
# specified on the command line, so process $@ to copy such arguments to
# JAVA_EXECUTABLE_ARGS.  -X flags are moved into JAVA_EXECUTABLE_ARGS.
# Quote some args, too, to preserve tokenization of arguments.
#
# COMMAND_LINE_ARGS is given the value of all args the user passes in on the
# command line (with the exception -X flags).  This will result in duplication
# of arguments starting with "-D" used in the JVM launch invocation below, but
# this is done to avoid possible errors.
#
COMMAND_LINE_ARGS=

for arg in "$@"
do
    case ${arg} in
        [\"]-D*=*[\"] | [\']-D*=*[\'] | -D*=[\"]*[\"] | -D*=[\']*[\'])
                  # These args are already quoted.
                  JAVA_EXECUTABLE_ARGS="${JAVA_EXECUTABLE_ARGS:+$JAVA_EXECUTABLE_ARGS }${arg}"
                  COMMAND_LINE_ARGS="${COMMAND_LINE_ARGS:+$COMMAND_LINE_ARGS }${arg}"
                  ;;
        -D*=*\ * | -D*=*[\(]*)
                  # These args need to be quoted properly.
                  if echo ${arg} | grep -e '"' >/dev/null
                  then
                      JAVA_EXECUTABLE_ARGS="${JAVA_EXECUTABLE_ARGS:+$JAVA_EXECUTABLE_ARGS }"`echo "${arg}" | sed -e "s/=\(.*\)$/=\'\1\'/"`
                      COMMAND_LINE_ARGS="${COMMAND_LINE_ARGS:+$COMMAND_LINE_ARGS }"`echo "${arg}" | sed -e "s/=\(.*\)$/=\'\1\'/"`
                  else
                      JAVA_EXECUTABLE_ARGS="${JAVA_EXECUTABLE_ARGS:+$JAVA_EXECUTABLE_ARGS }"`echo "${arg}" | sed -e "s/=\(.*\)$/=\"\1\"/"`
                      COMMAND_LINE_ARGS="${COMMAND_LINE_ARGS:+$COMMAND_LINE_ARGS }"`echo "${arg}" | sed -e "s/=\(.*\)$/=\"\1\"/"`
                  fi
                  ;;
        -D*=*)    # These args have no spaces and don't need quotes.
                  JAVA_EXECUTABLE_ARGS="${JAVA_EXECUTABLE_ARGS:+$JAVA_EXECUTABLE_ARGS }${arg}"
                  COMMAND_LINE_ARGS="${COMMAND_LINE_ARGS:+$COMMAND_LINE_ARGS }${arg}"
                  ;;
        -XX:*PrintVMOptions)
                  # Always give this argument precedence.
                  JAVA_EXECUTABLE_ARGS="${arg}${JAVA_EXECUTABLE_ARGS:+ $JAVA_EXECUTABLE_ARGS}"
                  ;;
        [\"]-X*[\"] | [\']-X*[\'])
                  # These args are already quoted, add to the JVM arg list.
                  JAVA_EXECUTABLE_ARGS="${JAVA_EXECUTABLE_ARGS:+$JAVA_EXECUTABLE_ARGS }${arg}"
                  ;;
        -X*\ *)   # This only belongs in the JVM arg list, doesn't need quotes.
                  if echo ${arg} | grep -e '"' >/dev/null
                  then
                      JAVA_EXECUTABLE_ARGS="${JAVA_EXECUTABLE_ARGS:+$JAVA_EXECUTABLE_ARGS }"`echo "${arg}" | sed -e "s/^\(.*\)$/\'\1\'/"`
                  else
                      JAVA_EXECUTABLE_ARGS="${JAVA_EXECUTABLE_ARGS:+$JAVA_EXECUTABLE_ARGS }"`echo "${arg}" | sed -e "s/^\(.*\)$/\"\1\"/"`
                  fi
                  ;;
        -X*)      # This only belongs in the JVM arg list, doesn't need quotes.
                  JAVA_EXECUTABLE_ARGS="${JAVA_EXECUTABLE_ARGS:+$JAVA_EXECUTABLE_ARGS }${arg}"
                  ;;
        [\"]*[\"] | [\']*[\'])
                  # These args are already quoted.
                  COMMAND_LINE_ARGS="${COMMAND_LINE_ARGS:+$COMMAND_LINE_ARGS }${arg}"
                  ;;
        *\ * | *[\(]*)
                  # These args need to be quoted properly.
                  if echo ${arg} | grep -e '"' >/dev/null
                  then
                      COMMAND_LINE_ARGS="${COMMAND_LINE_ARGS:+$COMMAND_LINE_ARGS }"`echo "${arg}" | sed -e "s/^\(.*\)$/\'\1\'/"`
                  else
                      COMMAND_LINE_ARGS="${COMMAND_LINE_ARGS:+$COMMAND_LINE_ARGS }"`echo "${arg}" | sed -e "s/^\(.*\)$/\"\1\"/"`
                  fi
                  ;;
        *)        COMMAND_LINE_ARGS="${COMMAND_LINE_ARGS:+$COMMAND_LINE_ARGS }${arg}"
                  ;;
    esac
done

#
# Verify network services are intialized before starting
#
echo Checking network services....
/usr/sbin/ipconfig waitall

#
# Launch the application.
#
echo Launching ${SCRIPT_NAME}.woa ...

echo ${JAVA_EXECUTABLE} ${JAVA_EXECUTABLE_ARGS} -classpath WOBootstrap.jar com.webobjects._bootstrap.WOBootstrap ${COMMAND_LINE_ARGS}
eval exec ${JAVA_EXECUTABLE} ${JAVA_EXECUTABLE_ARGS} -classpath WOBootstrap.jar com.webobjects._bootstrap.WOBootstrap ${COMMAND_LINE_ARGS}
