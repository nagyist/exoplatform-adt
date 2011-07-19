#!/bin/bash -e

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

    cygwin=false;
    linux=false;
    darwin=false;
    case "`uname`" in
        CYGWIN*) 
          cygwin=true;
          echo "[INFO] Environment : Cygwin";;
        Linux*) 
          linux=true;
          echo "[INFO] Environment : Linux";;
        Darwin*) 
          darwin=true;
          echo "[INFO] Environment : Darwin";;
    esac
    
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
      platform)
        GROUPID="org.exoplatform.platform"
        ARTIFACTID="exo.platform.packaging.assembly"
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
# Because Nexus REST APIs don't use Maven 3 metadata to download the latest SNAPSHOT
# of a given GAVCE we need to manually get the timestamp using xpath
# see https://issues.sonatype.org/browse/NEXUS-4423
#
do_download_server() {
  rm -f $DL_DIR/$PRODUCT-$VERSION.$PACKAGING
  mkdir -p $DL_DIR
  echo "[INFO] Downloading server ..."
  if [ -n $CREDENTIALS ]; then
    repository=private
    credentials="--user $CREDENTIALS --location-trusted"
  fi;
  if [ -z $CREDENTIALS ]; then
    repository=public
    credentials="--location"
  fi;
  url="http://repository.exoplatform.org/$repository/${GROUPID//.//}/$ARTIFACTID/$VERSION"
  echo "[INFO] Downloading metadata ..."
  curl $credentials "$url/maven-metadata.xml" > $DL_DIR/$PRODUCT-$VERSION-maven-metadata.xml
  if [ "$?" -ne "0" ]; then
    echo "Sorry, cannot download artifact metadata"
    exit 1
  fi
  echo "[INFO] Metadata downloaded"
  local QUERY="/metadata/versioning/snapshotVersions/snapshotVersion[(classifier=\"$CLASSIFIER\")and(extension=\"$PACKAGING\")]/value/text()"
  local FILENAME=$DL_DIR/$PRODUCT-$VERSION-maven-metadata.xml
  if $darwin; then
    TIMESTAMP=`xpath $FILENAME $QUERY`
  fi 
  if $linux; then
    TIMESTAMP=`xpath -q -e $QUERY $FILENAME`
  fi
  echo "[INFO] Latest timestamp : $TIMESTAMP"
  filename=$ARTIFACTID-$TIMESTAMP  
  name=$GROUPID:$ARTIFACTID:$VERSION
  if [ -n $CLASSIFIER ]; then
    filename="$filename-$CLASSIFIER"
    name="$name:$CLASSIFIER"
  fi;
  filename="$filename.$PACKAGING"
  name="$name:$PACKAGING"
  echo "[INFO] Archive          : $name "
  echo "[INFO] Repository       : $repository "
  curl $credentials "$url/$filename" > $DL_DIR/$PRODUCT-$VERSION.$PACKAGING
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
  rm -rf $TMP_DIR/$PRODUCT-$VERSION
  echo "[INFO] Unpacking server ..."
  mkdir -p $TMP_DIR/$PRODUCT-$VERSION
  case $PACKAGING in
    zip)
      unzip $DL_DIR/$PRODUCT-$VERSION.$PACKAGING -d $TMP_DIR/$PRODUCT-$VERSION
      ;;
    tar.gz)
      cd $TMP_DIR/$PRODUCT-$VERSION
      tar -xzvf $DL_DIR/$PRODUCT-$VERSION.$PACKAGING
      cd -
      ;;
    *)
      echo "[ERROR] Invalid packaging \"$PACKAGING\""
      print_usage
      exit 1
      ;;
  esac
  rm -rf $SRV_DIR/$PRODUCT-$VERSION
  mkdir -p $SRV_DIR
  find $TMP_DIR/$PRODUCT-$VERSION -maxdepth 1 -mindepth 1 -type d -exec cp -rf {} $SRV_DIR/$PRODUCT-$VERSION \;
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

do_create_apache_vhost()
{
mkdir -p $APACHE_CONF_DIR
cat << EOF > $APACHE_CONF_DIR/$PRODUCT-$VERSION.acceptance.exoplatform.org
<VirtualHost *:80>
    Include /home/swfcommons/etc/apache2/includes/default.conf
    ServerName  $PRODUCT-$VERSION.acceptance.exoplatform.org

    ErrorLog        \${APACHE_LOG_DIR}/$PRODUCT-$VERSION.acceptance.exoplatform.org-error.log
    LogLevel        warn
    CustomLog       \${APACHE_LOG_DIR}/$PRODUCT-$VERSION.acceptance.exoplatform.org-access.log combined  
    
    Alias /logs/ "$SRV_DIR/$PRODUCT-$VERSION/logs/"
    <Directory "$SRV_DIR/$PRODUCT-$VERSION/logs/">
        Options Indexes MultiViews
        AllowOverride None
        Order allow,deny
        Allow from all
    </Directory>
    
    #
    # Compression via GZIP
    #
    SetOutputFilter DEFLATE
    SetInputFilter DEFLATE
    DeflateFilterNote Input instream
    DeflateFilterNote Output outstream
    DeflateFilterNote Ratio ratio
    # Higher Compression 9 - Medium 5
    DeflateCompressionLevel 5

    ProxyRequests           Off
    ProxyPreserveHost       On
    ProxyPass               /exo-static/   !
    ProxyPass               /       ajp://localhost:$AJP_PORT/ acquire=1000 retry=30
    ProxyPassReverse        /       ajp://localhost:$AJP_PORT/
    <Proxy *>
        Order deny,allow
        Allow from all
    </Proxy>    
</VirtualHost>
EOF
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
  if [ ! $SKIP_DL ]; then
    do_download_server
  fi
  do_unpack_server
  do_patch_server
  do_create_apache_vhost
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
  echo "[INFO] URL  : http://$PRODUCT-$VERSION.acceptance.exoplatform.org"
  echo "[INFO] Logs : http://$PRODUCT-$VERSION.acceptance.exoplatform.org/logs/"
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
    do_start
    ;;
  stop) 
    do_stop
    ;;
  restart)
    do_stop
    do_start
    ;;
  *)
    echo "[ERROR] Invalid action \"$ACTION\"" 
    print_usage
    exit 1
    ;;
esac

exit 0