#!/bin/bash -eu

# Don't load it several times
set +u
${_FUNCTIONS_ONLYOFFICE_LOADED:-false} && return
set -u

# if the script was started from the base directory, then the
# expansion returns a period
if test "${SCRIPT_DIR}" == "."; then
  SCRIPT_DIR="$PWD"
  # if the script was not called with an absolute path, then we need to add the
  # current working directory to the relative path of the script
elif test "${SCRIPT_DIR:0:1}" != "/"; then
  SCRIPT_DIR="$PWD/${SCRIPT_DIR}"
fi

do_get_onlyoffice_settings() {
  if ! ${DEPLOYMENT_ONLYOFFICE_DOCUMENTSERVER_ENABLED}; then
    return;
  fi
  env_var DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME "${INSTANCE_KEY}_onlyoffice"
}

#
# Drops all Onlyoffice datas used by the instance.
#
do_drop_onlyoffice_data() {
  echo_info "Dropping onlyoffice data ..."
  if ${DEPLOYMENT_ONLYOFFICE_DOCUMENTSERVER_ENABLED}; then
    echo_info "Drops Onlyoffice container ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} ..."
    delete_docker_container ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}
    echo_info "Drops Onlyoffice docker volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_logs ..."
    delete_docker_volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_logs
    echo_info "Drops Onlyoffice docker volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_data ..."
    delete_docker_volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_data
    echo_info "Drops Onlyoffice docker volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_lib ..."
    delete_docker_volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_lib
    echo_info "Drops Onlyoffice docker volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_db ..."
    delete_docker_volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_db
    echo_info "Done."
    echo_info "Onlyoffice data dropped"
  else
    echo_info "Skip Drops Onlyoffice container ..."
  fi
}

do_create_onlyoffice() {
  if ${DEPLOYMENT_ONLYOFFICE_DOCUMENTSERVER_ENABLED}; then
    echo_info "Creation of the OnlyOffice Docker volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_logs ..."
    create_docker_volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_logs
    echo_info "Creation of the OnlyOffice Docker volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_data ..."
    create_docker_volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_data
    echo_info "Creation of the OnlyOffice Docker volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_lib ..."
    create_docker_volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_lib
    echo_info "Creation of the OnlyOffice Docker volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_db ..."
    create_docker_volume ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_db
  fi
}

do_stop_onlyoffice() {
  echo_info "Stopping OnlyOffice ..."
  if ! ${DEPLOYMENT_ONLYOFFICE_DOCUMENTSERVER_ENABLED}; then
    echo_info "Onlyoffice addon wasn't specified, skiping its server container shutdown"
    return
  fi
  ensure_docker_container_stopped ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}
  echo_info "OnlyOffice container ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} stopped."
}

do_start_onlyoffice() {
  echo_info "Starting OnlyOffice..."
  if ! ${DEPLOYMENT_ONLYOFFICE_DOCUMENTSERVER_ENABLED}; then
    echo_info "Onlyoffice addon not specified, skiping its server container startup"
    return
  fi

  # add onlyoffice security paramaters to exo server conf
  if [ -z "${DEPLOYMENT_ONLYOFFICE_SECRET}" ]
  then
    echo_error "Missing DEPLOYMENT_ONLYOFFICE_SECRET configured environment variable. OnlyOffice may not be deployed"
    exit 1
  fi 
  
  export DEPLOYMENT_OPTS="${DEPLOYMENT_OPTS} -Donlyoffice.documentserver.accessOnly=false -Donlyoffice.documentserver.secret=${DEPLOYMENT_ONLYOFFICE_SECRET}"

  echo_info "Starting OnlyOffice container ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} based on image ${DEPLOYMENT_ONLYOFFICE_IMAGE}:${DEPLOYMENT_ONLYOFFICE_IMAGE_VERSION}"

  # Ensure there is no container with the same name
  delete_docker_container ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}
  
  # Check for update
  ${DOCKER_CMD} pull ${DEPLOYMENT_ONLYOFFICE_IMAGE}:${DEPLOYMENT_ONLYOFFICE_IMAGE_VERSION} 2>/dev/null || true 

  local ONLYOFFICE_IMAGE_VERSION_MAJOR=$(echo $DEPLOYMENT_ONLYOFFICE_IMAGE_VERSION | cut -d '.' -f1)
  if [[ "${ONLYOFFICE_IMAGE_VERSION_MAJOR}" =~ ^[0-9]+$ ]] && [ "${ONLYOFFICE_IMAGE_VERSION_MAJOR}" -lt "7" ]; then 
    evaluate_file_content ${ETC_DIR}/onlyoffice/local.json.template ${DEPLOYMENT_DIR}/local.json
    ${DOCKER_CMD} run \
      -d \
      -p "${DEPLOYMENT_ONLYOFFICE_HTTP_PORT}:80" \
      -v ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_logs:/var/log/onlyoffice  \
      -v ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_data:/var/www/onlyoffice/Data  \
      -v ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_lib:/var/lib/onlyoffice  \
      -v ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_db:/var/lib/postgresql  \
      -v ${DEPLOYMENT_DIR}/local.json:/etc/onlyoffice/documentserver/local.json  \
      --name ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} ${DEPLOYMENT_ONLYOFFICE_IMAGE}:${DEPLOYMENT_ONLYOFFICE_IMAGE_VERSION}
  else 
    ${DOCKER_CMD} run \
      -d \
      -p "${DEPLOYMENT_ONLYOFFICE_HTTP_PORT}:80" \
      -e JWT_ENABLED="true" \
      -e JWT_SECRET="${DEPLOYMENT_ONLYOFFICE_SECRET}" \
      -e SECURE_LINK_SECRET=${DEPLOYMENT_ONLYOFFICE_LINK_SECRET} \
      -v ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_logs:/var/log/onlyoffice  \
      -v ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_data:/var/www/onlyoffice/Data  \
      -v ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_lib:/var/lib/onlyoffice  \
      -v ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_db:/var/lib/postgresql  \
      -h "onlyoffice" \
      --health-cmd="curl --silent --fail onlyoffice/healthcheck || exit 1" \
      --health-interval=30s \
      --health-timeout=30s \
      --health-retries=3 \
      --name ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} ${DEPLOYMENT_ONLYOFFICE_IMAGE}:${DEPLOYMENT_ONLYOFFICE_IMAGE_VERSION}
  fi 
  echo_info "${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} container started"
  # Hack: Onlyoffice starting from version 6 takes up to 1 minute to boot up. No need to wait it 
  if [ ${DEPLOYMENT_ONLYOFFICE_IMAGE_VERSION%%.*} -lt "6" ]; then
    check_onlyoffice_availability
  else 
    echo_info "Onlyoffice DocumentServer ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} up and available"
  fi
}

check_onlyoffice_availability() {
  echo_info "Waiting for Onlyoffice DocumentServer availability on port ${DEPLOYMENT_ONLYOFFICE_HTTP_PORT}"
  local count=0
  local try=600
  local wait_time=1
  local RET=-1

  local temp_file="/tmp/${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME}_${DEPLOYMENT_ONLYOFFICE_HTTP_PORT}.txt"

  while [ $count -lt $try -a $RET -ne 0 ]; do
    count=$(( $count + 1 ))
    set +e

    curl -s -q --max-time ${wait_time} http://localhost:${DEPLOYMENT_ONLYOFFICE_HTTP_PORT}  > /dev/null
    RET=$?
    if [ $RET -ne 0 ]; then
      [ $(( ${count} % 10 )) -eq 0 ] && echo_info "OnlyOffice documentserver not yet available (${count} / ${try})..."
    else
      curl -f -s --max-time ${wait_time} http://localhost:${DEPLOYMENT_ONLYOFFICE_HTTP_PORT}/healthcheck > ${temp_file} 
      local status=$(grep "true" ${temp_file})
      if [ "${status}" == "true" ]; then
        RET=0   
      fi
    fi

    if [ $RET -ne 0 ]; then
      echo -n "."
      sleep $wait_time
    fi
    set -e
  done
  if [ $count -eq $try ]; then
    echo_error "Onlyoffice DocumentServer ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} not available after $(( ${count} * ${wait_time}))s"
    exit 1
  fi
  echo_info "Onlyoffice DocumentServer ${DEPLOYMENT_ONLYOFFICE_CONTAINER_NAME} up and available"
}

# #############################################################################
# Env var to not load it several times
_FUNCTIONS_ONLYOFFICE_LOADED=true
echo_debug "_functions_onlyoffice.sh Loaded"
