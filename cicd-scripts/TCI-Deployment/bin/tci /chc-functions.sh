
#!/bin/bash
################################################################################
# Purpose
# This file contains common shell functions used by scripts that manage TCI
#
# Version 1.1.1 - 2023/10/16 - Pierre Ayel
#
# Changes:
#   Version 1.1.1 - 2023/10/16 - Pierre Ayel
#     create_app_force_overwrite: uses it own error handling on top of test_and_remove_http_code
#
#     invoke_tci_v1_rest_api: the response is written in the temp file /tmp/$$.tmp 
#     instead of being copied into a variable which leads to issues with the TCI/apps API response size
#
################################################################################

export HTTP_NOEXIT=""

readonly APP_STATUS_STOPPED="stopped"
export APP_STATUS_STOPPED

readonly APP_STATUS_RUNNING="running"
export APP_STATUS_RUNNING

# Private function
# Can be called *only* by public functions declared in this file
# Arguments:  HTTP code
#             HTTP method
#             HTTP path
#             HTTP body
function invoke_tci_v1_rest_api() {

  local http_code="${1}"
  local method="${2}"
  local path="${3}"

  curl -sS -w "\n%{http_code}" --location \
     --request "${method}" \
     "https://${CIC_TCI_V1_API_URL}/subscriptions/0/${path}" \
     --header "accept: application/json" \
     --header "Authorization: Bearer ${TCI_TOKEN}" \
     "${@:4}" > /tmp/$$.tmp

  test_and_remove_http_code "${http_code}" "" "${HTTP_NOEXIT}"
  rm /tmp/$$.tmp
}

function get_tci_token() {

  if [[ -n "${TCI_TOKEN-}" ]]; then
    local current_date
    current_date="$(date '+%Y-%m-%d-%H-%M-%S')"
    if [[ "${current_date}" < "${TCI_TOKEN_EXPIRE_DATE-}" ]]; then
      echoerr "Using cached TCI token"
      return
    else
      echoerr "TCI token has expired"
    fi
  fi

  echoerr "Getting TCI token"
  local response="$(
    curl -sS -w "\n%{http_code}" \
      "https://${CIC_IDM_V1_API_URL}/oauth2/token" \
      --header "Content-Type: application/x-www-form-urlencoded" \
      --data "grant_type=client_credentials&scope=TCI&client_id=${CIC_TCI_CLIENTID_CICD}&client_secret=${CIC_TCI_CLIENTSECRET_CICD}"
  )"

  response="$(test_and_remove_http_code "200" "${response}")"
  echoerr "Got TCI token"

  TCI_TOKEN="$(jq --raw-output '.access_token' <<<"${response}")"
  export TCI_TOKEN

  local expires_in
  expires_in=$(($(jq --raw-output '.expires_in' <<<"${response}") / 2))

  TCI_TOKEN_EXPIRE_DATE="$(date --date="+${expires_in} seconds" '+%Y-%m-%d-%H-%M-%S')"
  export TCI_TOKEN_EXPIRE_DATE
}

function get_app_artifact() {

  local app_name="${1}"
  local app_type="${2}"
  local app_version="${3}"
  local artifact

  case "${app_type}" in
  "${APPLICATION_TYPE_FLOGO}")
    artifact="${CI_PROJECT_DIR}/${CICD_DEPLOY_DIR}/flogo.json"
    ;;
  "${APPLICATION_TYPE_BUSINESSWORKS}")
    artifact="${CI_PROJECT_DIR}/${CICD_DEPLOY_DIR}/${app_name}_${app_version%-SNAPSHOT}.ear"
    ;;
  esac

  echo "${artifact}"
}

# Render hybrid agent access key
function render_hybrid_agent_access_key() {
  echo "${APP_AGENT_KEY}"
}
# Render Engine properties
function Engine_properties() {
  echo "${engine_json}"
}
# Public convenience function
# Render tci request body from template file and environment variables
function render_tci_request_body() {

  local template_file_path="${1}"
  local template_file=`basename "${template_file_path}"`

  echoerr "Rendering template file ${template_file}"
  
  cat "${template_file_path}" | envsubst | tee "/tmp/${template_file}"
}

# Get all apps
function get_apps() {

  echoerr "Getting apps"
  invoke_tci_v1_rest_api "200" "GET" "apps"
  echoerr "Got apps"
}

# Get app name from apps array
function get_app_by_name() {

  local app_name="${1}"
  export app_name
  local apps="${2}"

  echoerr "Getting app_name ${app_name} from apps"
  jq 'map(select(.appName==env.app_name))' <<<"${apps}"
}

# Get app_id by name from apps array
function get_app_id_by_name() {

  local app_name="${1}"
  export app_name
  local apps="${2}"

  echoerr "Getting app_id for app_name ${app_name}"

  local app_id
  app_id="$(jq --raw-output '.[] | select(.appName==env.app_name).appId | select(.!=null) | select(.!="")' <<<"${apps}")"

  if [[ -z "${app_id}" ]]; then
    app_id="${NOT_FOUND}"
  fi
  echo "${app_id}"
}

################################################################################
# Get app status

function get_app_status() {

  local app_id="${1}"
  local app_name=""
  [ "$#" -ge 2 ] && app_name="${2}"

  if [ -z "${app_name}" ] ; then
    echoerr "Getting app status for app_id ${app_id}"
  else
    echoerr "Getting app status for app_id ${app_id}, app_name ${app_name}"
  fi  
  invoke_tci_v1_rest_api "200" "GET" "apps/${app_id}/status"
}

################################################################################
# Create app with force overwrite

function create_app_force_overwrite() {

  local app_name="${1}"
  local artifact="artifact=@${2}"
  local manifest="manifest.json=@${3};type=application/json"

  echoerr "Creating app ${app_name}"
  local response
  
  HTTP_NOEXIT="noexit"
  if [ -f "${3}" ] ; then
  	response="$(invoke_tci_v1_rest_api "202" "POST" "apps?forceOverwrite=true&appName=${app_name}" --form "${artifact}" --form "${manifest}")"
  else	
  	response="$(invoke_tci_v1_rest_api "202" "POST" "apps?forceOverwrite=true&appName=${app_name}" --form "${artifact}")"
  fi
  HTTP_NOEXIT=""
  
  case "$(tail -n 1 <<<"${response}")" in
  error:504)
      echoerr "${response}" 
      echo "error:504"
      ;;

  error:*)
      echoerr "Expected HTTP 202 but got HTTP ${response#error:}: response=${response}"
      echoerr "Exiting ..."
      exit 1
      ;;
      
  *)
      echoerr "${response}"
      jq --raw-output '.appId' <<<"${response}"
      echoerr "Created app ${app_name}"
      ;;
  esac
}

################################################################################
# Copy app with app_id to a new app with app_name

function copy_app() {

  local app_id="${1}"
  local app_name=${2}

  echoerr "Copying app_id ${app_id} to app_name ${app_name}"

  local response
  response="$(invoke_tci_v1_rest_api "200" "POST" "apps/${app_id}/copy?appName=${app_name}")"
  echoerr "${response}"
  echo "${response}"
}

# Replace app
function replace_app() {

  local app_id="${1}"
  local source_app_id=${2}

  echoerr "Replacing app_id ${app_id} with source_app_id ${source_app_id}"
  invoke_tci_v1_rest_api "200" "POST" "apps/${app_id}/replace?sourceAppId=${source_app_id}"
}

# Delete app
function delete_app() {

  local app_id="${1}"

  echoerr "Deleting app_id ${app_id}"
  invoke_tci_v1_rest_api "202" "DELETE" "apps/${app_id}"
}

# Scale app
function scale_app() {

  local app_id="${1}"
  local instance_count="${2}"

  echoerr "Scaling app_id ${app_id} to ${instance_count} instances"
  invoke_tci_v1_rest_api "202" "POST" "apps/${app_id}/scale?instanceCount=${instance_count}"
}

function update_app_variables() {

  local app_id="${1}"
  local request_body="${2}"

  echoerr "Updating app variables for app_id ${app_id}"
  invoke_tci_v1_rest_api "202" "PUT" "apps/${app_id}/env/variables?variableType=app" --data "${request_body}"
}

function update_engine_variables() {

  local app_id="${1}"
  local request_body="${2}"

  echoerr "Updating engine variables for app_id ${app_id}"
  invoke_tci_v1_rest_api "202" "PUT" "apps/${app_id}/env/variables?variableType=engine" --data "${request_body}"
}

function create_user_defined_variables() {

  local app_id="${1}"
  local request_body="${2}"

  echoerr "Creating user defined variables for app_id ${app_id}"
  invoke_tci_v1_rest_api "202" "POST" "apps/${app_id}/env/variables" --data "${request_body}"
}

# Update app attributes
function update_app_attributes() {

  local app_id="${1}"
  local request_body="${2}"

  echoerr "Updating app attributes for app_id ${app_id}"
  invoke_tci_v1_rest_api "200" "PUT" "apps/${app_id}" --data "${request_body}"
}

# Update hybrid agent access key
function update_hybrid_agent_access_key() {

  local app_id="${1}"
  local tunnel_key="${2}"

  echoerr "Updating hybrid agent access key"
  invoke_tci_v1_rest_api "202" "PUT" "apps/${app_id}/env/tunnelkey?tunnelKey=${tunnel_key}"
}

# Validate desired state value
function validate_application_type() {

  local application_type="${1}"
  case "${application_type}" in
  "${APPLICATION_TYPE_FLOGO}") ;;
  "${APPLICATION_TYPE_BUSINESSWORKS}") ;;
  *)
    echoerr "Invalid application type ${application_type}: Valid values are ${APPLICATION_TYPE_FLOGO} or ${APPLICATION_TYPE_BUSINESSWORKS}"
    exit 1
    ;;
  esac
}

# Validate application tags declared in variable APP_CONF_TAGS
function validate_application_tags() {

  echo "Validating application tags"

  if [[ -z "${APP_CONF_TAGS-}" ]]; then
    echo "APP_CONF_TAGS must be set and not empty"
    echo "Exiting ..."
    exit 1
  fi

  local tags="${APP_CONF_TAGS}"
  local quoted_string="\"[a-zA-Z0-9_.-]+\""
  echo "Tags: ${tags}"
  IFS=","
  for tag in ${tags}; do
    if ! [[ "${tag}" =~ ${quoted_string} ]]; then
      echo "Tag ${tag} has invalid format"
      echo "Tag must be quoted and can only contain characters [a-z A-Z 0-9_.-]"
      echo "Exiting ..."
      exit 1
    fi
  done
  echo "Application tags are valid"
}

################################################################################
# Get pom element value
function chc_get_pom_element_value() {

  local element_name="${1}"
  local pom_file_path="${2}"

  echoerr "Getting value for element name ${element_name} from pom file ${pom_file_path}"
 
  local value
  value="$(xmlstarlet sel -t -v "count(/_:project/*[local-name() = '${element_name}'])" "${pom_file_path}")"
  if [[ "${value}" == 1 ]]; then
    xmlstarlet sel -t -v "/_:project/*[local-name() = '${element_name}']" "${pom_file_path}"
  else
    local parent
    parent="$(xmlstarlet sel -t -v "/_:project/_:parent/_:relativePath" "${pom_file_path}")"
    if [[ -n "${parent}" ]]; then
      local parent_pom
      parent_pom="$(dirname "${pom_file_path}")/${parent}/pom.xml"
      xmlstarlet sel -t -v "/_:project/*[local-name() = '${element_name}']" "${parent_pom}"
    fi
  fi
}

# Convenience function
function chc_get_pom_element_group_id() {
  chc_get_pom_element_value "groupId" "${1}"
}

# Convenience function
function chc_get_pom_element_artifact_id() {
  chc_get_pom_element_value "artifactId" "${1}"
}

# Convenience function
function chc_get_pom_element_version() {
  chc_get_pom_element_value "version" "${1}"
}

################################################################################
###  END OF FILE  ##############################################################
################################################################################
