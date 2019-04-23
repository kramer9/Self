#!/bin/bash
############################################################################
#
#               ------------------------------------------
#               THIS SCRIPT PROVIDED AS IS WITHOUT SUPPORT
#               ------------------------------------------
#
# Questions/feedback: http://ltc.linux.ibm.com/support/ltctools.php
#
# Version: 0.9.3
# Description: Wrapper script for subscription-manager to register RHEL 6
#              and RHEL 7 systems with the internal Red Hat Satellite using
#              FTP3 credentials.
#
# The following environment variables can be used:
#
#   FTP3USER=user@cc.ibm.com        FTP3 Account
#   FTP3PASS=mypasswd               FTP3 Password
#   FTP3FORCE=y                     FTP3 force registration
#
# You must be root to run this script. The user id and password will be
# prompted for if the environment variables are not set.
#
# example uses might be:
#
#  1.  ./ibm-rhsm.sh
#  2.  FTP3USER=user@cc.ibm.com ./ibm-rhsm.sh
#  3.  ./ibm-rhsm.sh --list-systems
#  4.  ./ibm-rhsm.sh --delete-systems
#
# The first example is a good way to test this script.
# The second example shows how to set the FTP3USER environment variable on
# the command line.
# The third example gets the list of registered systems you own.
# The fourth example removes all systems you own from your subscription.
#
# NOTE: Some parts of this script were extracted
#       from the good old ibm-yum.sh script.
#
############################################################################

## if xtrace flag activated the activate also verbose for debugging
[[ $(set -o |grep xtrace|cut -d' ' -f10|cut -f2) == "on" ]] && set -o verbose

## default host
[[ -z "$FTP3HOST" ]] && FTP3HOST="ftp3.linux.ibm.com"

## other vars that most likely should not change
API_URL="https://$FTP3HOST/rpc/index.php"
SERVER_NAME="ltc-rhs72.raleigh.ibm.com"
KATELLO_CERT_RPM="katello-ca-consumer-$SERVER_NAME"
IBM_RHSM_REG_LOG="ibm-rhsm.log"

## supported values
SUPPORTED_RELEASES=(6 7)
SUPPORTED_VERSIONS=(server workstation client)
SUPPORTED_ARCHS=(x86_64 ppc64le ppc64 s390x)

## registration status
## warmup: beginning of the process, mostly checking small things ; it has no meaning to clean up on exit
## progress: running the real stuff ; clean up and log data on exit
## ok: everything went fine
SUCCESS="warmup"

## CLI options
LIST_SYSTEMS=
DEL_SYSTEMS=

## Functions

## log string and/or command to $IBM_RHSM_REG_LOG
## logthis cmd arg1 arg2 ... : the command and its result will be logged
## logthis -s "string string string" : the string will be added to the log file
## logthis -s "string string string" cmd arg1 arg2 ... : combo!
## warning: | and " must be escaped
logthis() {
    if [[ $1 == "-s" ]]; then
        echo "$2" >> $IBM_RHSM_REG_LOG
        shift 2
    fi
    [[ $# -le 0 ]] && return
    echo "---- $*" >> $IBM_RHSM_REG_LOG
    eval $* &>> $IBM_RHSM_REG_LOG
}

## $1: string to print
## $2: color code as defined 0 = green; 1 = red; 2 = yellow
formatted_echo() {
    value=0
    case $2 in
        0) value=32 ;;
        1) value=31 ;;
        2) value=33 ;;
    esac
    echo -e "\r\t\t\t\t\t\t\t\e[${value}m$1\e[0m"
}

## $1: KEY or DEL or SYSTEMS
## $2: username
## $3: password
## $4: data (could be empty)
run_curl() {
    user=$2
    pass=$3
    data=
    case "$1" in
        KEY)
            command="user.create_activation_key"
            ;;
        DEL)
            command="user.delete_registered_systems"
            data="<param><value>$4</value></param>"
            ;;
        SYSTEMS)
            command="user.list_registered_systems"
            ;;
        *)
            return 1
    esac
    result=$(curl -ks $API_URL -H "Content-Type: text/xml" -d "<?xml version='1.0' encoding='UTF-8'?><methodCall><methodName>${command}</methodName> <params><param><value>$user</value></param> <param><value>$pass</value></param> $data </params> </methodCall>")
    if [[ $? -ne 0 ]]; then
        case "$1" in
            KEY)
                echo "An error has occurred while trying to create the activation key."
                ;;
            DEL)
                echo "An error has occurred while trying to delete registered systems."
                ;;
            SYSTEMS)
                echo "An error has occurred while trying to get the list of registered systems."
                ;;
        esac
        return 1
    fi
    echo "$result" | grep -oPm1 "(?<=<string>)[^<]+"
    return 0
}

## $1: KEY or DEL or SYSTEMS
## $2: exit code from curl
## $3: curl result
check_curl_result() {
    [[ "$1" != "KEY" && "$1" != "DEL" && "$1" != "SYSTEMS" ]] && return
    if [[ $2 -ne 0 ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

$3
Aborting...

EOF
        exit $2
    elif [[ -z "$3" ]]; then
        formatted_echo "FAIL" 1
        echo
        case "$1" in
            KEY)
                cat <<EOF
An error has occurred: No activation key.
There was a problem while creating your activation key.
Please, make sure you are connected to the IBM network and using a valid FTP3 account.
Aborting.
EOF
                ;;
            DEL)
                echo "No registered systems found."
                ;;
            SYSTEMS)
                echo "No registered systems found."
                ;;
        esac
        echo
        exit 1
    elif [[ "$3" == "Account not found" || "$3" == "Wrong username or password" ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: $3
Please, make sure you're using the correct FTP3 username and password.
Aborting.

EOF
        exit 1
    elif [[ "$3" == "The account $FTP3USER does not have access to Red Hat content" ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: $3
You may request access on the "My Account" page: https://$FTP3HOST/myaccount/access.php.
Aborting.

EOF
        exit 1
    elif [[ "$3" == "No activation key was found" ]]; then # This could only happen if $1 is DEL or SYSTEMS
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: No activation key.
Please, make sure you are connected to the IBM network and using a valid FTP3 account.
Aborting.

EOF
        exit 1
    elif [[ "$3" == "Two (or more) activation keys were found" ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: $3
You may open a ticket here: https://ltc.linux.ibm.com/support/ltctools.php?Tool=FTP3
Please, add this message to the new ticket.
Aborting.

EOF
        exit 1
    elif [[ "$1" == "DEL" && "$3" == "Unable to find this system: "* ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: $3
Please, make sure you own the system you're trying to delete and that you're using the correct hostname.
To check which registered systems you own: $0 --list-systems

EOF
         exit 1
    elif [[ "$1" == "DEL" && "$3" == *"KO:"* ]]; then
         if [[ "$3" == *"OK:"* ]]; then
             formatted_echo "WARN" 2
         else
             formatted_echo "FAIL" 1
         fi
    else
         formatted_echo "OK" 0
    fi
}

## print usage
usage() {
    cat <<EOF
Usage: $0 [--list-systems] [--delete-systems [<system>]]
  --list-systems                  print the registered systems you own.
  --delete-systems [<system>]     delete all the registered systems you own or
                                  just the given one.
  The options are mutually exclusive.
  Without the options, it will try to register the current system.

EOF
    exit 1
}

## this is called on exit
clean_up() {
    [[ "$SUCCESS" == "ok" ]] && exit 0

    if [[ "$SUCCESS" == "progress" ]]; then
        logthis -s "-- Cleaning on exit ----------------------------------------------------"
        if rpm --quiet -q $KATELLO_CERT_RPM; then
            echo "Cleaning up..."
            logthis -s "$KATELLO_CERT_RPM is installed, removing."
            rpm --quiet -e $KATELLO_CERT_RPM
        fi
        logthis subscription-manager facts
        logthis tail -30 /var/log/rhsm/rhsm.log
    fi
    exit 1
}

## clean up proper if something goes bad
trap clean_up EXIT HUP INT QUIT TERM;

## must be root to run this
if [[ $(whoami) != "root" ]] ; then
    echo "You must run this script as root. Goodbye."
    echo
    exit 1
fi

## check CLI options
while [[ $# -gt 0 ]]; do
    if [[ "$1" == -* ]]; then
        case "$1" in
            --list-systems)
                if [[ -n "$DEL_SYSTEMS" ]]; then
                    echo "The options are mutually exclusive"
                    usage
                fi
                LIST_SYSTEMS=1
                shift
               ;;
            --delete-systems)
                if [[ -n "$LIST_SYSTEMS" ]]; then
                    echo "The options are mutually exclusive"
                    usage
                fi
                DEL_SYSTEMS=1
                shift
                if [[ -n "$1" ]]; then
                    DEL_SYSTEMS="$1"
                    shift
                fi
                ;;
            *)
                echo "Invalid option: $1"
                usage
                ;;
        esac
    else
        break
    fi
done
[[ $# -gt 0 ]] && usage

## Force path with /usr/sbin for subscription-manager need
export PATH=/usr/sbin:$PATH

## initialize the log file
rm -f $IBM_RHSM_REG_LOG
logthis -s "-- IBM-RHSM.LOG --------------------------------------------------------"
logthis -s "On $(date)"
logthis -s "Script version: $(grep -m1 Version $0)"
logthis -s "System: $(uname -a)"
logthis lscpu
logthis cat /etc/redhat-release

## get the userid
if [[ -z "$FTP3USER" ]] ; then
    echo -n "User ID: "
    read FTP3USER

    if [[ -z "$FTP3USER" ]] ; then
        cat <<EOF

Missing userid.
Either set the environment variable FTP3USER to your user id
or enter a user id when prompted.
Goodbye.

EOF
        exit 1
    fi
fi

## get the password
if [[ -z "$FTP3PASS" ]] ; then
    echo -n "Password for $FTP3USER: "
    stty -echo
    read -r FTP3PASS
    stty echo
    echo

    if [[ -z "$FTP3PASS" ]] ; then
        cat <<EOF

Missing password.
Either set the environment variable FTP3PASS to your user password
or enter a password when prompted.
Goodbye.

EOF
        exit 1
    fi
fi

## Encode the username for use in URLs
FTP3USERENC=$(echo $FTP3USER | sed s/@/%40/g)

## Encode user password for use in URLs
FTP3PASSENC=$(echo $FTP3PASS | od -tx1 -An | tr -d '\n' | sed 's/ /%/g')

if [[ -n "$LIST_SYSTEMS" ]]; then
    echo -n "Searching for registered systems... "

    RESULT=$(run_curl SYSTEMS $FTP3USERENC $FTP3PASSENC)
    RET=$?
    logthis -s "-- List systems --------------------------------------------------------"
    logthis -s "return code: $RET"
    logthis -s "result: $RESULT"
    check_curl_result SYSTEMS $RET "$RESULT"
    echo
    echo $RESULT | tr ' ' '\n' | sort -h | sed "s/^/    /"
    echo
    exit 0
fi

if [[ -n "$DEL_SYSTEMS" ]]; then
    echo -n "Deleting registered systems... "

    [[ "$DEL_SYSTEMS" == "1" ]] && DEL_SYSTEMS=
    RESULT=$(run_curl DEL $FTP3USERENC $FTP3PASSENC $DEL_SYSTEMS)
    RET=$?
    logthis -s "-- Delete systems ------------------------------------------------------"
    logthis -s "return code: $RET"
    logthis -s "result: $RESULT"
    check_curl_result DEL $RET "$RESULT"
    echo $RESULT | tr ' ' '\n' | sed -e "s/^/    /" -e "s/    OK:/\nDeleted systems:/" -e "s/    KO:/\nUnable to delete systems:/"
    echo
    [[ "$RESULT" == *"KO:"* ]] && exit 1
    exit 0
fi

SUCCESS="progress"

if [[ ! -x /usr/sbin/subscription-manager ]]; then
    logthis -s "-- subscription-manager ------------------------------------------------"
    logthis -s "/usr/sbin/subscription-manager is missing"
    logthis rpm -q subscription-manager
    cat <<EOF
The subscription-manager command can't be found.
Check with your administrator to install this package: subscription-manager

EOF
    exit 1
fi

echo "Starting the registration process..."

echo -n "* Performing initial checks... "
logthis -s "-- Checking hostname ---------------------------------------------------"
HOSTNAME=$(hostname 2>/dev/null)
if [[ $? -ne 0 ]]; then
    formatted_echo "FAIL" 1
    cat <<EOF
Failed to find system hostname.
Please run the command "hostname" to set and check the system hostname.

EOF
    logthis -s "Error while calling: hostname"
    exit 1
fi
# get long hostname if -f is available
tmp=$(hostname -f 2>/dev/null)
[[ $? -eq 0 ]] && HOSTNAME=$tmp
logthis -s "Hostname: $HOSTNAME"

## is the system already registered?
logthis -s "-- Checking if the system is already registered ------------------------"
RESULT=$(run_curl SYSTEMS $FTP3USERENC $FTP3PASSENC)
logthis -s "registered systems: $RESULT"
if grep -qw $HOSTNAME <<< "$RESULT"; then
    formatted_echo "WARN" 2
    echo "This system is already registered or currently un-registring."
    logthis -s "current system is already registered"
    PROCEED="y"
    if [[ "${FTP3FORCE,,}" != "y" ]]; then
        echo -n "Would like to proceed? (y/n): "
        read PROCEED
    fi
    if [[ "${PROCEED,,}" != "y" ]]; then
        echo "Aborting..."
        echo
        exit 1
    fi
    # Clean subscription data as status not always relevant
    echo -n "* Unregistering the system... "
    logthis -s "-- Cleaning subscription -----------------------------------------------"
    logthis subscription-manager unregister
    logthis subscription-manager unsubscribe --all
    logthis subscription-manager clean
    logthis yum clean all
else
    logthis -s "current system isn't registered"
fi
formatted_echo "OK" 0

echo -n "* Checking the current system... "
logthis -s "-- Checking release, version and arch ----------------------------------"
## get the version and release, most likely only works on RHEL
VERREL=$(rpm -qf --qf "%{NAME}-%{VERSION}" /etc/redhat-release)
if [[ $? -ne 0 ]] ; then
    formatted_echo "FAIL" 1
    cat <<EOF
Failed to find system version and release with the
command "rpm -q redhat-release". Is this system
running Red Hat Enterprise Linux?

EOF
    logthis -s "Error while calling: rpm -qf --qf \"%{NAME}-%{VERSION}\" /etc/redhat-release"
    logthis -s "Result: $VERREL"
    exit 1
fi

## split something like "redhat-release-server-7.1" into "7" and "server"
RELEASE=$(echo $VERREL | cut -f4 -d"-" | cut -b1)
VERSION=$(echo $VERREL | cut -f3 -d"-")
VALID=

## verify support for this release and this version
grep -qvw $RELEASE <<< ${SUPPORTED_RELEASES[@]} && VALID=no && logthis -s "Unknown or unsupported release: $RELEASE"
grep -qvw $VERSION <<< ${SUPPORTED_VERSIONS[@]} && VALID=no && logthis -s "Unknown or unsupported version: $VERSION"
if [[ -n "$VALID" ]] ; then
    formatted_echo "FAIL" 1
    cat <<EOF
Unknown or unsupported system version and release: $VERREL
This could be reported at: http://ltc.linux.ibm.com/support/ltctools.php
Please do not forget to add the $IBM_RHSM_REG_LOG file to the request.

EOF
    exit 1
fi

## get the system arch
ARCH=$(uname -m)

## verify support for this arch
grep -qvw $ARCH <<< ${SUPPORTED_ARCHS[@]} && VALID=no && logthis -s "Unknown or unsupported arch: $ARCH"
[[ "$VERSION" == "client" && "$ARCH" != "x86_64" ]] && VALID=no && logthis -s "Unsupported combo version+arch: $VERSION+$ARCH"
if [[ -n "$VALID" ]] ; then
    formatted_echo "FAIL" 1
    cat <<EOF
Unsupported system architecture: $ARCH
This could be reported at: http://ltc.linux.ibm.com/support/ltctools.php
Please do not forget to add the $IBM_RHSM_REG_LOG file to the request.

EOF
    exit 1
fi

## set LABEL
case $ARCH in
    x86_64 ) LABEL="$VERSION" ;;
    ppc64le)
        if [[ $(subscription-manager facts | grep lscpu.model_name | cut -f2 -d' '| cut -f1 -d',') == "POWER9" ]] ; then
            LABEL="for-power-9"
        else
            LABEL="for-power-le"
        fi
        ;;
    ppc64  ) LABEL="for-power" ;;
    s390x  ) LABEL="for-system-z" ;;
esac

formatted_echo "OK" 0
logthis -s "Detected a RHEL $RELEASE $VERSION on $ARCH, $LABEL"

## system is registered to the old RHN Satellite?
logthis -s "-- Checking the system is registered to the old RHN --------------------"
if rpm --quiet -q rhn-org-trusted-ssl-cert; then
    echo "This system is registered to the old RHN Satellite." | tee -a $IBM_RHSM_REG_LOG
    echo -n "Would like to proceed and remove current associations? (y/n): "
    read PROCEED

    if [[ "${PROCEED,,}" != "y" ]]; then
        echo "Aborting..."
        echo
        exit 1
    fi
    logthis yum remove rhn-org-trusted-ssl-cert -y
else
    logthis -s "No"
fi

## Force disabling of rhn plugin
if [[ -f /etc/yum/pluginconf.d/rhnplugin.conf ]]; then
    sed -i 's/enabled\ =\ 1/enabled\ =\ 0/g' /etc/yum/pluginconf.d/rhnplugin.conf
fi

echo -n "* Checking the server certificate... "
logthis -s "-- Checking the certificate --------------------------------------------"
if ! rpm --quiet -q $KATELLO_CERT_RPM; then
    formatted_echo "WARN" 2
    logthis -s "The server certificate is not installed."

    logthis -s "* Removing traces of previous certificates."
    logthis rpm -e $(rpm -qa | grep katello-ca)
    if [[ $? -eq 0 ]]; then
        rm -fr /etc/pki/consumer/*
    fi

    echo -n "* Installing server certificate... "
    logthis rpm -Uv http://$SERVER_NAME/pub/katello-ca-consumer-latest.noarch.rpm
    RET=$?
    logthis subscription-manager config
    if [[ $RET -ne 0 ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF
An error has occurred while trying to install the server certificate.
This could be reported at: http://ltc.linux.ibm.com/support/ltctools.php
Please do not forget to add the $IBM_RHSM_REG_LOG file to the request.
Aborting...

EOF
        exit 1
    else
        formatted_echo "OK" 0
    fi
else
    formatted_echo "OK" 0
    logthis -s "Server certificate is already installed."
fi

## Get activation key
## in case an existing key is not found, a new one will be created.
echo -n "* Searching for an activation key... "
logthis -s "-- Activation key ------------------------------------------------------"
ACTIVATION_KEY=$(run_curl KEY $FTP3USERENC $FTP3PASSENC)
RET=$?
logthis -s "return code: $RET"
logthis -s "activation key (or error message): $ACTIVATION_KEY"
logthis -s "(You may copy this activation key for future use)"
check_curl_result KEY $RET "$ACTIVATION_KEY"

## system registration
echo -n "* Registering the system... "
logthis -s "-- Registering the system ----------------------------------------------"
REGSTATUS=$(subscription-manager register --org Default_Organization --activationkey="$ACTIVATION_KEY" --force 2>&1)
if [[ $(grep -c "The system has been registered" <<< "$REGSTATUS") -ne 1 ]]; then
    formatted_echo "FAIL" 1
    logthis -s "Registration failed!"
    logthis -s "Registration error: $REGSTATUS"
    cat <<EOF
An error has occurred while trying to register the system.
You may try to register it later using the following command:
subscription-manager register --org Default_Organization --activationkey="$ACTIVATION_KEY" --force
This could be reported at: http://ltc.linux.ibm.com/support/ltctools.php
Please do not forget to add the $IBM_RHSM_REG_LOG file to the request.

EOF
    exit 1
else
    logthis -s "System successfully registered"
    formatted_echo "OK" 0
fi

logthis subscription-manager facts \| egrep "\"distribution|net\""

## Disable all repositories
echo -n "* Disabling all repositories... "
logthis -s "-- Disabling repositories ----------------------------------------------"
logthis subscription-manager repos --disable="\"*\""
if [[ $? -ne 0 ]]; then
    formatted_echo "FAIL" 1
    logthis subscription-manager repos --list \| grep "\"Repo ID:\""
else
    formatted_echo "OK" 0
fi

## Enable RHEL repositories
echo "* Enabling RHEL $RELEASE repositories"
logthis -s "-- list of current repos available --"
logthis subscription-manager repos --list
logthis -s "-- Enabling repositories -----------------------------------------------"
[[ $LABEL == "for-power-9" ]] && extra="" || extra="supplementary"
[[ $(subscription-manager repos --list |grep rhel-$RELEASE-$LABEL-extras-rpms) ]] && extra="$extra extras"
for REPO in common optional $extra; do
    echo -n "    ${REPO^}... "
    [[ $REPO != "common" ]] && str="$REPO-" || str=""
    logthis subscription-manager repos --enable=rhel-$RELEASE-$LABEL-${str}rpms
    [[ $? -eq 0 ]] && formatted_echo "OK" 0 || formatted_echo "FAIL" 1
done

echo
echo "Registration completed!" | tee -a $IBM_RHSM_REG_LOG

echo "If you need to add more repositories like extras you can issue commands like:" | tee -a $IBM_RHSM_REG_LOG
echo "subscription-manager repos --enable=rhel-$RELEASE-$LABEL-extras-rpms" | tee -a $IBM_RHSM_REG_LOG

SUCCESS="ok"

exit 0
