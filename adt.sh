#! /bin/bash

SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="${0%/*}"

# if the script was started from the base directory, then the
# expansion returns a period
if test "$SCRIPT_DIR" == "." ; then
  SCRIPT_DIR="$PWD"
# if the script was not called with an absolute path, then we need to add the
# current working directory to the relative path of the script
elif test "${SCRIPT_DIR:0:1}" != "/" ; then
  SCRIPT_DIR="$PWD/$SCRIPT_DIR"
fi

# ADT_DATA is the working area for ADT script
if [ ! $ADT_DATA ]; then
  echo "[ERROR] ADT_DATA environment variable not set !"
  exit 1;
fi
mkdir -p $ADT_DATA

TMP_DIR=$ADT_DATA/tmp
DL_DIR=$ADT_DATA/downloads
SRV_DIR=$ADT_DATA/servers
CONF_DIR=$ADT_DATA/conf
APACHE_CONF_DIR=$ADT_DATA/conf/apache

SHUTDOWN_PORT=8005
HTTP_PORT=8080
AJP_PORT=8009

#
# Usage message
#
print_usage()
{
cat << EOF
usage: $0 <options> <product> <version> <action>

This script manages deployment of acceptance instances

OPTIONS :
  -h         Show this message
  -A         AJP Port
  -H         HTTP Port
  -S         SHUTDOWN Port 
  -u         user credentials (value in "username:password" format) to download the server package (default: none)

PRODUCT :
  social     eXo Social
  ecms       eXo Content
  ks         eXo Knowledge
  cs         eXo Collaboration
  platform   eXo Platform

VERSION :
  version of the product

ACTIONS :
  start      Starts the server
  stop       Stops the server
EOF
}

#
# Decode command line parameters
#
do_init()
{
    #
    # without enough parameters, provide help
    #
    if [ $# -lt 3 ]; then
      print_usage
      exit 1;
    fi

    while getopts "hsA:H:S:u:" OPTION
    do
         case $OPTION in
             h)
                 print_usage
                 exit 1
                 ;;
             H)
                 HTTP_PORT=$OPTARG
                 ;;
             A)
                 AJP_PORT=$OPTARG
                 ;;
             S)
                 SHUTDOWN_PORT=$OPTARG
                 ;;
             u)
                 CREDENTIALS=$OPTARG
                 ;;
             ?)
                 print_usage
                 exit
                 ;;
         esac
    done

    # skip getopt parms
    shift $((OPTIND-1))

    # Product to deploy
    PRODUCT=$1
    
    # Version to deploy
    shift
    VERSION=$1

    # Action to do
    shift
    ACTION=$1

    # Validate args    
    case "$PRODUCT" in
      social)
        GROUPID="org.exoplatform.social"
        ARTIFACTID="exo.social.packaging.pkg"
        CLASSIFIER="tomcat"
        PACKAGING="zip"
        ;;
      ecms)
        GROUPID="org.exoplatform.ecms"
        ARTIFACTID="exo-ecms-delivery-wcm-assembly"
        CLASSIFIER="tomcat"
        PACKAGING="zip"
        ;;
      stop)
        ;;
      *)
        echo "[ERROR] Invalid action \"$PACKAGING\"" 
        print_usage
        exit 1
        ;;
    esac
}

#
# Function that downloads the app server from nexus
#
do_download_server() {
  rm -f $DL_DIR/$PRODUCT-$VERSION.$PACKAGING

  echo "[INFO] Downloading server ..."
  if [ -n $CREDENTIALS ]; then
    repository=private
    credentials="--user $CREDENTIALS --location-trusted"
  fi;
  if [ -z $CREDENTIALS ]; then
    repository=public
    credentials="--location"
  fi;
  params="g=$GROUPID&a=$ARTIFACTID&v=$VERSION&r=$repository"
  name="$GROUPID:$ARTIFACTID:$VERSION"
  if [ -n $CLASSIFIER ]; then
    params="$params&c=$CLASSIFIER"
    name="$name:$CLASSIFIER"
  fi;
  if [ -n $PACKAGING ]; then
    params="$params&p=$PACKAGING"
    name="$name:$PACKAGING"
  fi;
  echo "[INFO] Archive    : $name "
  echo "[INFO] Repository : $repository "
  mkdir -p $DL_DIR
  curl --progress-bar $credentials "http://repository.exoplatform.org/service/local/artifact/maven/redirect?$params" > $DL_DIR/$PRODUCT-$VERSION.$PACKAGING
  if [ "$?" -ne "0" ]; then
    echo "Sorry, cannot download $name"
    exit 1
  fi
  echo "[INFO] Server downloaded"
}

#
# Function that unpacks the app server archive
#
do_unpack_server() 
{
  rm -rf $TMP_DIR/$PRODUCT-$VERSION $SRV_DIR/$PRODUCT-$VERSION
  echo "[INFO] Unpacking server ..."
  mkdir -p $TMP_DIR/$PRODUCT-$VERSION
  case $PACKAGING in
    zip)
      unzip -q $DL_DIR/$PRODUCT-$VERSION.$PACKAGING -d $TMP_DIR/$PRODUCT-$VERSION
      ;;
    tar.gz)
      cd $TMP_DIR/$PRODUCT-$VERSION
      tar -xzf $DL_DIR/$PRODUCT-$VERSION.$PACKAGING
      cd -
      ;;
    *)
      echo "[ERROR] Invalid packaging \"$PACKAGING\""
      print_usage
      exit 1
      ;;
  esac
  mkdir -p $SRV_DIR
  find $TMP_DIR/$PRODUCT-$VERSION -type d -depth 1 -exec cp -rf {} $SRV_DIR/$PRODUCT-$VERSION \;
  rm -rf $TMP_DIR/$PRODUCT-$VERSION
  echo "[INFO] Server unpacked"
}

#
# Function that configure the server for ours needs
#
do_patch_server()
{
  sed -i -e "s|8005|${SHUTDOWN_PORT}|g" $SRV_DIR/$PRODUCT-$VERSION/conf/server.xml
  sed -i -e "s|8080|${HTTP_PORT}|g" $SRV_DIR/$PRODUCT-$VERSION/conf/server.xml
  sed -i -e "s|8009|${AJP_PORT}|g" $SRV_DIR/$PRODUCT-$VERSION/conf/server.xml
}

#
# Function that configure the app server archive
#
do_configure_server()
{
  echo "[INFO] Configuring server ..."
  echo "[INFO] Server configured"
}

#
# Function that starts the app server
#
do_start()
{
  echo "[INFO] Starting server ..."
  chmod 755 $SRV_DIR/$PRODUCT-$VERSION/bin/*.sh
  $SRV_DIR/$PRODUCT-$VERSION/bin/gatein.sh start
  #STARTING=true
  #while [ $STARTING ];
  #do    
  #  if [ -e $SRV_DIR/$PRODUCT-$VERSION/logs/catalina.out ]; then
  #    if grep -q "Server startup in" $SRV_DIR/$PRODUCT-$VERSION/logs/catalina.out; then
  #      STARTING=false
  #    fi    
  #  fi    
  #  echo -n .
  #  sleep 5    
  #done
  echo "[INFO] Server started"
}

#
# Function that stops the app server
#
do_stop()
{
  if [ -e $SRV_DIR/$PRODUCT-$VERSION ]; then
    echo "[INFO] Stopping server ..."
    $SRV_DIR/$PRODUCT-$VERSION/bin/gatein.sh stop
    echo "[INFO] Server stopped"
  else
    echo "[WARN] No server directory to stop it"
  fi
}

do_init $@

case "$ACTION" in
  start)
    if [ ! $SKIP_DL ]; then
      do_download_server
    fi
    do_unpack_server
    do_start
    ;;
  restart)
    do_stop
    if [ ! $SKIP_DL ]; then
      do_download_server
    fi
    do_unpack_server
    do_patch_server
    do_start
    ;;
  stop) 
    do_stop
    ;;
  *)
    echo "[ERROR] Invalid action \"$ACTION\"" 
    print_usage
    exit 1
    ;;
esac

exit 0