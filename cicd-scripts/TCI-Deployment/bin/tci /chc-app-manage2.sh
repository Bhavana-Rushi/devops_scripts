
#!/bin/bash
################################################################################
# Version 1.1.1 - 2023/10/16 - Pierre Ayel
#
# Changes:
#   Version 1.1.1 - 2023/10/16 - Pierre Ayel
#     Updated deploy_app function with new error handling
#
#   Version 1.1.0 - 2023/10/13 - Pierre Ayel
#     If temp app deployment call returns 504 (timeout) the script will try to 
#     get the temp app id from existing apps, so it can continue its configuration 
#
################################################################################

set -eou pipefail
set -o posix
echo "Pierre 504 error script"

typeset DIRSCRIPT=`dirname "${0}"`
DIRSCRIPT=`(cd "${DIRSCRIPT}" ; pwd)`

readonly SCRIPT=`basename "${0}"`

# Source cicd functions
# shellcheck disable=SC1090
source "${DIRSCRIPT}/../functions.sh"
# Source tcm functions
# shellcheck disable=SC1090
source "${DIRSCRIPT}/chc-functions.sh"

# catch exit status
trap on_exit EXIT

readonly ACTION_DEPLOY="deploy"
readonly ACTION_UNDEPLOY="undeploy"
readonly ACTION_SHOW_ENDPOINTS="endpoints"
readonly ACTION_SHOW_PUBLIC_ENDPOINTS="public-endpoints"
readonly ACTION_SHOW_PUBLIC_ENDPOINTS_PATH="public-endpoints-path"

readonly WAIT_FOR_STATUS_RETRY_COUNT="${WAIT_FOR_STATUS_RETRY_COUNT:-120}"
#readonly WAIT_FOR_STATUS_RETRY_COUNT="${WAIT_FOR_STATUS_RETRY_COUNT:-5}"
readonly WAIT_FOR_STATUS_RETRY_DELAY="${WAIT_FOR_STATUS_RETRY_DELAY:-5}"

readonly WAIT_FOR_APPID_RETRY_COUNT="${WAIT_FOR_APPID_RETRY_COUNT:-10}"
readonly WAIT_FOR_APPID_RETRY_DELAY="${WAIT_FOR_APPID_RETRY_DELAY:-60}"

export APPLICATION_TYPE=businessworks
export APPLICATION_TYPE_BUSINESSWORKS=businessworks
export APPLICATION_TYPE_FLOGO=flogo

export CIC_IDM_V1_API_URL=${CIC_IDM_V1_API_URL:-eu.account.cloud.tibco.com/idm/v1}
export CIC_TCI_V1_API_URL=${CIC_TCI_V1_API_URL:-eu.api.cloud.tibco.com/tci/v1}

export APP_ENG_BWCE_APP_CPU_ALERT_THRESHOLD=${APP_ENG_BWCE_APP_CPU_ALERT_THRESHOLD:-70}
export APP_ENG_BWCE_APP_MEM_ALERT_THRESHOLD=${APP_ENG_BWCE_APP_MEM_ALERT_THRESHOLD:-70}
export APP_ENG_BWCE_ENGINE_STEPCOUNT=${APP_ENG_BWCE_ENGINE_STEPCOUNT:--1}
export APP_ENG_BWCE_ENGINE_THREADCOUNT=${APP_ENG_BWCE_ENGINE_THREADCOUNT:-8}
export APP_ENG_BWCE_INSTRUMENTATION_ENABLED=${APP_ENG_BWCE_INSTRUMENTATION_ENABLED:-true}
export APP_ENG_BWCE_LOGGER_OVERRIDES="${APP_ENG_BWCE_LOGGER_OVERRIDES:-ROOT=WARN com.tibco.bw.palette.generalactivities.Log=INFO}"
export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY:-}"
#export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY:-com.tibco.tibjms.connect.attemptcount=20}"
#export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY1="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY1:-com.tibco.tibjms.connect.attemptdelay=1000}" 
#export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY2="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY2:-com.tibco.tibjms.connect.attempttimeout=1000}" 
#export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY3="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY3:-com.tibco.tibjms.reconnect.attemptcount=600}" 
#export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY4="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY4:-com.tibco.tibjms.reconnect.attemptdelay=1000}" 
#export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY5="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY5:-com.tibco.tibjms.reconnect.attempttimeout=1000}"


export APP_CONF_INSTANCECOUNT=${APP_CONF_INSTANCECOUNT:-1}

export APP_CONF_NAME="${APP_CONF_NAME:-}"

export APP_AGENT_KEY="${APP_AGENT_KEY:-}"

export APP_CONF_ENDPOINTVISIBILITY="${APP_CONF_ENDPOINTVISIBILITY:-mesh}"

export CICD_TCI_TEMPLATE_DIR=`(cd "${DIRSCRIPT}/../../template" ; pwd)`

################################################################################
# Handle non-zero exit status

typeset errmsg=""
typeset show_usage=false

function on_exit() {

  local exit_status="$?"
  if [[ "${exit_status}" -ne 0 ]]; then
  
    [ -n "${errmsg}" ] && echoerr "${errmsg}"
    [ "${show_usage}" = "true" ] && usage
  
    separatelog
    echoerr "Handling exit status ${exit_status}"
    separatelog

    if [ -n "${temp_app_name:-}" ] ; then	    
      local apps="$(get_apps)"
      separatelog
      undeploy_app "${temp_app_name}" "${apps}" "wait_for_stopped_status"
    fi  
    
    echoerr "Handled exit status ${exit_status}"
  fi
}

################################################################################

function usage() {
   echoerr ""
   echoerr "Usage: ${SCRIPT} ${ACTION_DEPLOY} <app-name> <app-properties.json> <ear-file> <manifest.json>"
   echoerr "       ${SCRIPT} ${ACTION_UNDEPLOY} <app-name>"
   echoerr "       ${SCRIPT} ${ACTION_SHOW_ENDPOINTS} <app-name>"
   echoerr "       ${SCRIPT} ${ACTION_SHOW_PUBLIC_ENDPOINTS} <app-name>"
   echoerr "       ${SCRIPT} ${ACTION_SHOW_PUBLIC_ENDPOINTS_PATH} <app-name>"
   echoerr "       ${SCRIPT} [-nowait] start <app-name>"
   echoerr "       ${SCRIPT} [-nowait] stop <app-name>"
   echoerr "       ${SCRIPT} [-nowait] scale <app-name> <instance_count>"
   echoerr ""
   exit 1
}

################################################################################
# Validates a file exists, is readable and is not empty

function validate_file() {
   local file="${1}"
   
   if [ ! -f "${file}" ] ; then
     errmsg="File ${file} does not exist or cannot be found"
     exit 1
   fi
   if [ ! -r "${file}" ] ; then
     errmsg="File ${file} is not readable" && 
     exit 1
   fi  
   if [ ! -s "${file}" ] ; then
     errmsg="File ${file} is empty" && 
     exit 1
   fi  
}

################################################################################

function validate_action() {

  local action="${1}"
  case "${action}" in
  "${ACTION_DEPLOY}") ;;
  "${ACTION_UNDEPLOY}") ;;
  "${ACTION_SHOW_ENDPOINTS}") ;;
  "${ACTION_SHOW_PUBLIC_ENDPOINTS}") ;;
  "${ACTION_SHOW_PUBLIC_ENDPOINTS_PATH}") ;;
  "stop") ;;
  "start") ;;
  "scale") ;;
  *)
    errmsg="Invalid action: ${action}"
    show_usage="true"
    exit 1
    ;;
  esac
}

################################################################################

function render_engine_variables_request_body() {

  local app_type="${1}"
  local request_body

  case "${app_type}" in
  "${APPLICATION_TYPE_FLOGO}")
    # value of this variable is a json object so we need to escape quotes
    export APP_ENG_FLOGO_APP_METRICS_LOG_EMITTER_CONFIG="${APP_ENG_FLOGO_APP_METRICS_LOG_EMITTER_CONFIG//\"/\\\"}"
    request_body="$(render_tci_request_body "flogo-engine-variables.json")"
    ;;
  "${APPLICATION_TYPE_BUSINESSWORKS}")
    if [[ -n "${APP_ENG_BWCE_COMPONENT_JOB_FLOWLIMIT-}" ]]; then
      # if flow limit is set add it to custom engine property variable
      local bwce_custom_engine_property="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY} bw.component.job.flowlimit=${APP_ENG_BWCE_COMPONENT_JOB_FLOWLIMIT}"
      # remove leading spaces
      APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY="${bwce_custom_engine_property##*( )}"
      export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY
    fi
    #export APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY="${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY} ${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY1} ${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY2} ${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY3} ${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY4} ${APP_ENG_BWCE_CUSTOM_ENGINE_PROPERTY5}"
    #request_body="$(render_tci_request_body "${DIRSCRIPT}/../../template/businessworks-engine-variables.json")"
    local Engine_properties="$(Engine_properties)"
    request_body="$(render_tci_request_body "${Engine_properties}")"
    ;;
  esac
  echoerr "${request_body}"
  echo "${request_body}"
}

################################################################################
# Render app name based on information from group id and app name

function render_app_name() {

  if [ -n "${APP_CONF_NAME}" ] ; then
  	echo "${APP_CONF_NAME}"
  else

    local app_name="${1}"
    local group_id="${2}"

    local app_name_prefix=""

    # echo group_id, reverse string, delete everything after first dot, reverse string, get first three characters
    #app_name_prefix="$(echo "${group_id}" | rev | cut -d"." -f1 | rev | cut -c1-3)"
    # capitalize first character of prefix
    #app_name_prefix="${app_name_prefix^}"

    local tci_app_name
    tci_app_name="${app_name_prefix}${app_name}"
    echo "${tci_app_name}"
  fi  
}

################################################################################

function deploy_app() {

  local pom_app_name="${1}"
  local app_name="${2}"
  local temp_app_name="${3}"
  local app_type="${4}"
  local app_version="${5}"
  local apps="${6}"

  local application_properties_json_path="${7}"
  echoerr "application_properties_json_path=${application_properties_json_path}"

  local artifact
  artifact="${8}"
  echoerr "artifact=${artifact}"
  local manifest="${9}"
  echoerr "manifest=${manifest}"

  # create temp app
  separatelog
  local temp_app_id="$(create_app_force_overwrite "${temp_app_name}" "${artifact}" "${manifest}")"
  local HTTP_CODE=""
  
  case "${temp_app_id}" in
  error:*)
     HTTP_CODE="${temp_app_id#error:}"
     temp_app_id=""
     ;;
  esac
  
  # 2023/10/13: if deployment failed (for example 504), we have no temp_app_id
  # 2023/10/13: so we loop until we get the temp_app_id
  if [ "${temp_app_id}" = "" -a "${HTTP_CODE}" = "504" ] ; then
  	for retry in $(seq 1 "${WAIT_FOR_APPID_RETRY_COUNT}"); do
	
	    echoerr "----------------"
	    echoerr "Deployment is running but TCI API timed out (504), retrieving temp_app_id..."
	    echoerr "----------------"

	    echoerr "Retry retrieving temp_app_id ${retry} in ${WAIT_FOR_APPID_RETRY_DELAY}s ..."
	    sleep "${WAIT_FOR_APPID_RETRY_DELAY}"

	    apps="$(get_apps)"
  	    temp_app_id="$(get_app_id_by_name "${temp_app_name}" "${apps}")"
  	    
	    if [[ "${temp_app_id}" != "" ]]; then
    	      echoerr "Get appid of created app ${app_name}"


	      break
	    fi
  	done
  fi	
  
  if [ "${temp_app_id}" = "" ] ; then
  	echoerr DEPLOYMENT FAILURE OR TIMEOUT
  	exit 1
  fi
  
  ###  wait for temp app status to be stopped
  separatelog
  wait_for_stopped_status "${temp_app_id}" "${temp_app_name}"

  local request_body

  separatelog
  if [[ -f "${application_properties_json_path}" ]]; then
    request_body="$(<"${application_properties_json_path}")"
    # update temp app variables declared in application-properties.json file
    update_app_variables "${temp_app_id}" "${request_body}"
    separatelog
    wait_for_stopped_status "${temp_app_id}" "${temp_app_name}"
  else
    echoerr "File ${application_properties_json_path} not found - omitting update app variables ..."
  fi

  # update engine variables for a given application type
  separatelog
  request_body="$(render_engine_variables_request_body "${app_type}")"
  separatelog
  update_engine_variables "${temp_app_id}" "${request_body}"
  sh -x ${DIRSCRIPT}/chc-updatecustomproperties-unique.sh "${temp_app_name}"
  separatelog
  wait_for_stopped_status "${temp_app_id}" "${temp_app_name}"

  export CI_COMMIT_TAG="${CI_COMMIT_TAG:=NO_TAG}"

  # create user variables
  separatelog
  request_body="$(render_tci_request_body "${DIRSCRIPT}/../../template/user-defined-variables.json")"
  separatelog
  create_user_defined_variables "${temp_app_id}" "${request_body}"
  separatelog
  wait_for_stopped_status "${temp_app_id}" "${temp_app_name}"

  # update hybrid agent access key
  local agent_key="$(render_hybrid_agent_access_key)"
  if [ -n "${agent_key}" ] ; then
    separatelog
    update_hybrid_agent_access_key "${temp_app_id}" "${agent_key}"
    separatelog
    wait_for_stopped_status "${temp_app_id}" "${temp_app_name}"
  fi  

  # update app attributes
  separatelog
  request_body="$(render_tci_request_body "${DIRSCRIPT}/../../template/app-attributes.json")"
  separatelog
  update_app_attributes "${temp_app_id}" "${request_body}"
  separatelog
  wait_for_stopped_status "${temp_app_id}" "${temp_app_name}"

  # update the custom properties
  #bash ${DIRSCRIPT}/chc-updatecustomproperties-unique.sh "${temp_app_name}" "${TCI_TOKEN}"
  bash ${DIRSCRIPT}/Update-engine-custom.sh "${temp_app_name}" "${engine_properties}" "${TCI_TOKEN}"
  separatelog
  export app_name
  local app_id
  app_id="$(get_app_id_by_name "${app_name}" "${apps}")"
  echoerr "app_id=${app_id}"

  separatelog
  local desired_instance_count=0

  if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
    echoerr "App ${app_name} does not exist"
    app_id="$(copy_app "${temp_app_id}" "${app_name}" | jq --raw-output '.appId')"
    separatelog
    wait_for_stopped_status "${app_id}" "${app_name}"
    separatelog
    # we replace the newly copied app in order for flogo password properties to be naturally encrypted
    replace_app "${app_id}" "${temp_app_id}"
    separatelog
    wait_for_stopped_status "${app_id}" "${app_name}"
  else
    echoerr "App ${app_name} exists"
    local app
    app="$(get_app_by_name "${app_name}" "${apps}")"
    separatelog
    desired_instance_count="$(jq --raw-output '.[] | .desiredInstanceCount' <<<"${app}")"
    echoerr "desired_instance_count=${desired_instance_count}"
    replace_app "${app_id}" "${temp_app_id}"
    separatelog
    if [[ "${desired_instance_count}" == 0 ]]; then
      wait_for_stopped_status "${app_id}" "${app_name}"
    else
      wait_for_running_status "${app_id}" "${app_name}"
    fi
  fi

  separatelog
  local instance_count="${APP_CONF_INSTANCECOUNT}"
  echoerr "desired_instance_count=${desired_instance_count}"
  echoerr "instance_count=${instance_count}"
  separatelog
  if [[ "${desired_instance_count}" -ne "${instance_count}" ]]; then
    echoerr "Desired instance count and instance count do not match - scaling ..."
    separatelog
    echoerr "Scaling ${app_name} from ${desired_instance_count} to ${instance_count} instances"
    scale_app "${app_id}" "${instance_count}"
    separatelog
    wait_for_running_status "${app_id}" "${app_name}"
  else
    echoerr "Desired instance count and instance count match - omitting scaling ..."
  fi

  separatelog
  echoerr "Deployed app ${app_name}"

  separatelog
  undeploy_app "${temp_app_name}" "$(get_apps)"
}

################################################################################

function undeploy_app() {

  local app_name="${1}"
  local apps="${2}"

  local app_id
  app_id="$(get_app_id_by_name "${app_name}" "${apps}")"

  separatelog
  if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
    echoerr "App ${app_name} not found"
    separatelog
    return 0
  else
    echoerr "App ${app_name} found"
    echoerr "Undeploying app ${app_name}"
    # if wait for status function is passed execute it with app_id
    if [[ $# == 3 ]]; then
      separatelog
      local wait_for_status_function="${3}"
      echoerr "wait_for_status_function=${wait_for_status_function}"
      # shellcheck disable=SC2091
      $(eval "${wait_for_status_function} ${app_id} ${app_name}")
    fi
    separatelog
    delete_app "${app_id}"
  fi

  separatelog
  echoerr "Waiting for app ${app_name} to be undeployed"
  separatelog
  for retry in $(seq 1 "${WAIT_FOR_STATUS_RETRY_COUNT}"); do

    app_id="$(get_app_id_by_name "${app_name}" "$(get_apps)")"

    if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
      separatelog
      echoerr "Undeployed ${app_name}"
      separatelog
      return 0
    fi

    echoerr "Retry ${retry} in ${WAIT_FOR_STATUS_RETRY_DELAY}s ..."
    sleep "${WAIT_FOR_STATUS_RETRY_DELAY}"
  done

  if [[ "${retry}" -ge "${WAIT_FOR_STATUS_RETRY_COUNT}" ]]; then
    echoerr "Reached retry count while waiting for status ${status}"
    echoerr "Exiting ..."
    exit
  fi
}

################################################################################

function show_app_endpoints() {

  local app_name="${1}"

    separatelog
    get_tci_token

    separatelog
    local apps="$(get_apps)"
    separatelog

  local app_id="$(get_app_id_by_name "${app_name}" "${apps}")"

  separatelog
  if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
    echoerr "App ${app_name} not found"
    separatelog
    return 0
  else
    echoerr "App ${app_name} found"
    echoerr "Listing endpoints"
    
    invoke_tci_v1_rest_api "200" "GET" "apps/${app_id}/endpoints" | jq .
  fi
}

################################################################################

function show_app_public_endpoints() {

  local app_name="${1}"

    separatelog
    get_tci_token

    separatelog
    local apps="$(get_apps)"
    separatelog

  local app_id="$(get_app_id_by_name "${app_name}" "${apps}")"

  separatelog
  if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
    echoerr "App ${app_name} not found"
    separatelog
    return 0
  else
    echoerr "App ${app_name} found"
    echoerr "Listing endpoints"
    
    local endpoints="$(invoke_tci_v1_rest_api "200" "GET" "apps/${app_id}/endpoints")"
    echo "${endpoints}" | jq 'keys[]' | while read KEY ; do
      local base=`echo "${endpoints}" | jq --raw-output ".[${KEY}].apiSpec.basePath"`
      local host=`echo "${endpoints}" | jq --raw-output ".[${KEY}].apiSpec.host"`
    
      base="${base#*/tci/}"
      base="${base#/}"
      echo ${host}/${base}
    done  
  fi
}

################################################################################

function show_app_public_endpoints_path() {

  local app_name="${1}"

    separatelog
    get_tci_token

    separatelog
    local apps="$(get_apps)"
    separatelog

  local app_id="$(get_app_id_by_name "${app_name}" "${apps}")"

  separatelog
  if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
    echoerr "App ${app_name} not found"
    separatelog
    return 0
  else
    echoerr "App ${app_name} found"
    echoerr "Listing endpoints"
    
    local endpoints="$(invoke_tci_v1_rest_api "200" "GET" "apps/${app_id}/endpoints")"
    echo "${endpoints}" | jq 'keys[]' | while read KEY ; do
      local base=`echo "${endpoints}" | jq --raw-output ".[${KEY}].apiSpec.basePath"`
      local host=`echo "${endpoints}" | jq --raw-output ".[${KEY}].apiSpec.host"`

      local paths=`echo "${endpoints}" | jq ".[${KEY}].apiSpec.paths" | jq --raw-output 'keys[]'`
    
      base="${base#*/tci/}"
      base="${base#/}"
      echo "${paths}" | while read path ; do
       	echo ${host}/${base}${path}
      done
    done  
  fi
}

################################################################################

function action_stop_app() {

  local app_name="${1}"
  local wait="${2}"

  separatelog
  get_tci_token

  separatelog
  local apps="$(get_apps)"
  separatelog

  local app_id="$(get_app_id_by_name "${app_name}" "${apps}")"

  separatelog
  if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
    echoerr "App ${app_name} not found"
    separatelog
    return 0
  else
    echoerr "App ${app_name} found"
    echoerr "Stopping"
    
    invoke_tci_v1_rest_api "202" "POST" "apps/${app_id}/stop"

    [ "${wait}" = "true" ] && wait_for_stopped_status "${app_id}" "${app_name}"
  fi
}

################################################################################

function action_start_app() {

  local app_name="${1}"
  local wait="${2}"

  separatelog
  get_tci_token

  separatelog
  local apps="$(get_apps)"
  separatelog

  local app_id="$(get_app_id_by_name "${app_name}" "${apps}")"

  separatelog
  if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
    echoerr "App ${app_name} not found"
    separatelog
    return 0
  else
    echoerr "App ${app_name} found"
    echoerr "Starting"
    
    invoke_tci_v1_rest_api "202" "POST" "apps/${app_id}/start"
    
    [ "${wait}" = "true" ] && wait_for_running_status "${app_id}" "${app_name}"
  fi
}

################################################################################

function action_scale_app() {

  local app_name="${1}"
  local instance_count="${2}"
  local wait="${3}"

  separatelog
  get_tci_token

  separatelog
  local apps="$(get_apps)"
  separatelog

  local app_id="$(get_app_id_by_name "${app_name}" "${apps}")"

  separatelog
  if [[ "${app_id}" == "${NOT_FOUND}" ]]; then
    echoerr "App ${app_name} not found"
    separatelog
    return 0
  else
    echoerr "App ${app_name} found"
    echoerr "Scaling to ${instance_count}"
    
    scale_app "${app_id}" "${instance_count}"
    
    case "${instance_count}" in
    0) [ "${wait}" = "true" ] && wait_for_stopped_status "${app_id}" "${app_name}"
       ;;
    *) [ "${wait}" = "true" ] && wait_for_running_status "${app_id}" "${app_name}"
       ;;
    esac   
  fi
}

################################################################################

function wait_for_status() {

  local status="${1}"
  local app_id="${2}"
  local app_name=""
  [ "$#" -ge 3 ] && app_name="${3}"

  for retry in $(seq 1 "${WAIT_FOR_STATUS_RETRY_COUNT}"); do

    local current_status_object="$(get_app_status "${app_id}" "${app_name}")"

    local current_status="$(jq --raw-output '.status' <<<"${current_status_object}")"
    echoerr "----------------"
    echoerr "Waiting for status ${status}"
    echoerr "----------------"
    echoerr "Status is ${current_status}"
    local current_instance_status="$(jq --raw-output '.instanceStatus' <<<"${current_status_object}")"
    echoerr "Instance status is ${current_status_object}"
    echoerr "----------------"

    if [[ "${current_status}" == "${status}" ]]; then
      break
    fi
    echoerr "Retry ${retry} in ${WAIT_FOR_STATUS_RETRY_DELAY}s ..."
    sleep "${WAIT_FOR_STATUS_RETRY_DELAY}"
  done

  if [[ "${retry}" -ge "${WAIT_FOR_STATUS_RETRY_COUNT}" ]]; then
    echoerr "Reached retry count while waiting for status ${status}"
    echoerr "Exiting ..."
    exit 1
  fi
}

################################################################################

function wait_for_stopped_status() {
  wait_for_status "${APP_STATUS_STOPPED}" "$@"
}

################################################################################

function wait_for_running_status() {
  wait_for_status "${APP_STATUS_RUNNING}" "$@"
}

################################################################################

function main() {

  # parse arguments for options
  local i
  local wait="true"
  for i in "$@" ; do
  	case "${i}" in
  	"-nowait") wait="false" ; shift ;;
  	esac
  done

  [ "$#" -lt "2" ] && usage

  local action="${1}"
  local app_name="${2}"
  local app_type="${APPLICATION_TYPE}"

  validate_action "${action}"

  separatelog
  validate_application_type "${app_type}"

  case "${action}" in
  "${ACTION_DEPLOY}")

    local propfile="${3}"
    local earfile="${4}"
    local manifestfile="${5}"

    # check application property file is a valid file and a valid JSON file
    if [ -f "${propfile}" ] ; then
       validate_file "${propfile}"
       
       errmsg="Application property file is not a valid JSON file: ${propfile}"
       show_usage="true"
    
       echoerr "Checking application property file is a correct JSON file: ${propfile}"
       jq '.' "${propfile}" >/dev/null
    fi  
    errmsg=""
    show_usage="false"

    # check earfile
    if [ -z "${earfile}" ] ; then
      errmsg="Empty EAR file name and path"
      show_usage="true"
      exit 1
    fi
    errmsg=""
    show_usage="false"
    validate_file "${earfile}"

    # check manifest file is a valid file and a valid JSON file 
    if [ -f "${manifestfile}" ] ; then
       validate_file "${manifestfile}"
       
       errmsg="Application manifest file is not a valid JSON file: ${manifestfile}"
       show_usage="true"

       echoerr "Checking manifest file is a correct JSON file: ${propfile}"
       jq '.' "${manifestfile}" >/dev/null
    fi  
    errmsg=""
    show_usage="false"

    # create temporary application name 
    local temp_app_name="${app_name}_temp"
    export temp_app_name

    echoerr "app_name=${app_name}"
    echoerr "temp_app_name=${temp_app_name}"
    echoerr "app_type=${app_type}"

    separatelog
    get_tci_token

    separatelog
    local apps="$(get_apps)"
    separatelog

    # undeploy temp app if it exists
    undeploy_app "${temp_app_name}" "${apps}" "wait_for_stopped_status"
  
    deploy_app "${app_name}" "${app_name}" "${temp_app_name}" "${app_type}" "1.0" "${apps}" "${propfile}" "${earfile}" "${manifestfile}"
    ;;
  "${ACTION_UNDEPLOY}")

    local temp_app_name="${app_name}_temp"
    export temp_app_name

    echoerr "app_name=${app_name}"
    echoerr "temp_app_name=${temp_app_name}"
    echoerr "app_type=${app_type}"

    separatelog
    get_tci_token

    separatelog
    local apps="$(get_apps)"
    separatelog

    # undeploy temp app if it exists
    undeploy_app "${temp_app_name}" "${apps}" "wait_for_stopped_status"
    
    undeploy_app "${app_name}" "${apps}"
    ;;
  "${ACTION_SHOW_ENDPOINTS}")

    echoerr "app_name=${app_name}"
    echoerr "app_type=${app_type}"

    show_app_endpoints "${app_name}"
    ;;
    
  "${ACTION_SHOW_PUBLIC_ENDPOINTS}")

    echoerr "app_name=${app_name}"
    echoerr "app_type=${app_type}"

    show_app_public_endpoints "${app_name}"
    ;;
    
  "${ACTION_SHOW_PUBLIC_ENDPOINTS_PATH}")

    echoerr "app_name=${app_name}"
    echoerr "app_type=${app_type}"

    show_app_public_endpoints_path "${app_name}"
    ;;
    
  "stop")
    echoerr "app_name=${app_name}"
    echoerr "app_type=${app_type}"

    action_stop_app "${app_name}" "wait"
    ;;
    
  "start")
    echoerr "app_name=${app_name}"
    echoerr "app_type=${app_type}"
    
    action_start_app "${app_name}" "wait"
    ;;
    
  "scale")
    [ "$#" -lt "3" ] && usage
    
    local instance_count="${3}"
    
    # validate syntax of instance_count
    case "${instance_count}" in
    [0-9]*) ;;
    *)     echoerr "Invalid instance count: need zero or positive integer: ${instance_count}"
           exit 1
           ;;
    esac       
  
    echoerr "app_name=${app_name}"
    echoerr "app_type=${app_type}"
    
    action_scale_app "${app_name}" "${instance_count}" "wait"
    ;;
  esac
}

################################################################################

main "$@"

################################################################################
###  END OF FILE  ##############################################################
################################################################################
