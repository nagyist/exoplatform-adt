#!/bin/bash -eu

# Don't load it several times
set +u
${_FUNCTIONS_MATRIX_LOADED:-false} && return
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

do_get_matrix_settings() {
  if ! ${DEPLOYMENT_MATRIX_ENABLED:-false} ; then
    return;
  fi
  env_var DEPLOYMENT_MATRIX_CONTAINER_NAME "${INSTANCE_KEY}_matrix"
  env_var DEPLOYMENT_MAILPIT_CONTAINER_NAME "${INSTANCE_KEY}_mailpit"
}

do_drop_matrix_data() {
  echo_info "Dropping matrix data ..."
  if [ "${DEPLOYMENT_MATRIX_ENABLED}" == "true" ] ; then
    echo_info "Drops matrix container ${DEPLOYMENT_MATRIX_CONTAINER_NAME} ..."
    delete_docker_container ${DEPLOYMENT_MATRIX_CONTAINER_NAME}
    echo_info "Drops Matrix docker volume ${DEPLOYMENT_MATRIX_CONTAINER_NAME}_data ..."
    delete_docker_volume ${DEPLOYMENT_MATRIX_CONTAINER_NAME}_data
    echo_info "Done."
    echo_info "matrix data dropped"
  else
    echo_info "Skip Drops matrix container ..."
  fi
}

do_create_matrix() {
  if ${DEPLOYMENT_MATRIX_ENABLED}; then
    echo_info "Creation of the Matrix Docker volume ${DEPLOYMENT_MATRIX_CONTAINER_NAME}_data ..."
    create_docker_volume ${DEPLOYMENT_MATRIX_CONTAINER_NAME}_data
  fi
}

do_stop_matrix() {
  echo_info "Stopping matrix ..."
  if ! ${DEPLOYMENT_MATRIX_ENABLED}; then
    echo_info "matrix wasn't specified, skiping its server container shutdown"
    return
  fi
  ensure_docker_container_stopped ${DEPLOYMENT_MATRIX_CONTAINER_NAME}
  echo_info "matrix container ${DEPLOYMENT_MATRIX_CONTAINER_NAME} stopped."
}

do_start_matrix() {
  echo_info "Starting matrix..."
  if [ "${DEPLOYMENT_MATRIX_ENABLED}" == "false" ]; then
    echo_info "matrix not specified, skiping its containers startup"
    return
  fi
  mkdir -p ${DEPLOYMENT_DIR}/matrix
  evaluate_file_content ${ETC_DIR}/matrix/homeserver.yaml.template ${DEPLOYMENT_DIR}/matrix/homeserver.yaml
  evaluate_file_content ${ETC_DIR}/matrix/initialize.sh.template ${DEPLOYMENT_DIR}/matrix/initialize.sh
  chmod +x ${DEPLOYMENT_DIR}/matrix/initialize.sh
  evaluate_file_content ${ETC_DIR}/matrix/client.template ${DEPLOYMENT_DIR}/matrix/client
  evaluate_file_content ${ETC_DIR}/matrix/server.template ${DEPLOYMENT_DIR}/matrix/server
  echo_info "Starting Matrix container ${DEPLOYMENT_MATRIX_CONTAINER_NAME} based on image ${DEPLOYMENT_MATRIX_IMAGE}"

  # Ensure there is no container with the same name
  delete_docker_container ${DEPLOYMENT_MATRIX_CONTAINER_NAME}

  cp -v ${ETC_DIR}/matrix/matrix.host.signing.key ${DEPLOYMENT_DIR}/matrix/matrix.host.signing.key
  cp -v ${ETC_DIR}/matrix/matrix.log.config ${DEPLOYMENT_DIR}/matrix/matrix.log.config

  #Change Matrix data directory to 12000
  ${DOCKER_CMD} run --rm -v ${DEPLOYMENT_MATRIX_CONTAINER_NAME}_data:/data alpine \
  sh -c "chown -R 12000:12000 /data"

  local SMTP_SERVER='0.0.0.0'
  if [ "${DEPLOYMENT_MAILPIT_ENABLED}" == "true" ]; then
      SMTP_SERVER=$(${DOCKER_CMD} inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${DEPLOYMENT_MAILPIT_CONTAINER_NAME})
  else
      # to do for SMTP relay
      echo_info "Mailpit wasn't enabled, No email sending is configured in Matrix"
  fi
  ${DOCKER_CMD} run \
    -d \
    --user 12000:12000 \
    -v ${DEPLOYMENT_DIR}/matrix/homeserver.yaml:/data/homeserver.yaml:ro \
    -v ${DEPLOYMENT_DIR}/matrix/matrix.host.signing.key:/data/matrix.host.signing.key:ro \
    -v ${DEPLOYMENT_DIR}/logs:/var/log/matrix \
    -v ${DEPLOYMENT_DIR}/matrix/matrix.log.config:/data/matrix.log.config:ro \
    -v ${DEPLOYMENT_MATRIX_CONTAINER_NAME}_data:/data:rw \
    -v ${DEPLOYMENT_DIR}/matrix/initialize.sh:/docker-entrypoint-init.d/initialize.sh:ro \
    -p "${DEPLOYMENT_MATRIX_HTTP_PORT}:8008" \
    --add-host=smtpserver:${SMTP_SERVER} \
    --health-cmd="curl -fSs http://localhost:8008/health || exit 1" \
    --health-interval=15s \
    --health-timeout=5s \
    --health-retries=3 \
    --health-start-period=5s \
    --hostname matrix \
    --entrypoint "/bin/bash" \
    --name ${DEPLOYMENT_MATRIX_CONTAINER_NAME} ${DEPLOYMENT_MATRIX_IMAGE}:${DEPLOYMENT_MATRIX_IMAGE_VERSION} \
    -c "/docker-entrypoint-init.d/initialize.sh"


  echo_info "${DEPLOYMENT_MATRIX_CONTAINER_NAME} container started"


  check_matrix_availability
}

check_matrix_availability() {
  echo_info "Waiting for Matrix availability on port ${DEPLOYMENT_MATRIX_HTTP_PORT}"
  local count=0
  local try=600
  local RET=-1

  while [ $count -lt $try -a $RET -ne 0 ]; do
    count=$((count + 1))
    set +e
    curl -fSs http://localhost:${DEPLOYMENT_MATRIX_HTTP_PORT}/health &>/dev/null
    RET=$?
    if [ $RET -ne 0 ]; then
      [ $((count % 10)) -eq 0 ] && echo_info "Matrix not yet available (${count} / ${try})..."
      echo -n "."
      sleep 1
    fi
    set -e
  done

  if [ $count -eq $try ]; then
    echo_error "Matrix container ${DEPLOYMENT_MATRIX_CONTAINER_NAME} not available after $((count)) retries."
    exit 1
  fi

  echo_info "Matrix container ${DEPLOYMENT_MATRIX_CONTAINER_NAME} up and available."
}

# This function is used to reset the matrix data
# It will drop the matrix data and create a new one
# To be replaced by a dump/restore function
do_reset_matrix_data() {
  do_drop_matrix_data
  do_create_matrix
}

# #############################################################################
# Env var to not load it several times
_FUNCTIONS_MATRIX_LOADED=true
echo_debug "_function_matrix.sh Loaded"
