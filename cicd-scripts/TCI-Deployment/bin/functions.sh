
#!/bin/bash
################################################################################
# Purpose
# This file contains common shell functions used by cicd scripts
#
# Version 1.1.2 - 2023/10/17 - Pierre Ayel
#
# Changes:
#   Version 1.1.2 - 2023/10/17 - Pierre Ayel
#     test_and_remove_http_code: in case of error, the HTTP response is printed out
#
#   Version 1.1.1 - 2023/10/16 - Pierre Ayel
#     test_and_remove_http_code: added option for not exiting in case of error
#     the HTTP_CODE variable does not work and is removed
#     if noexit is on, the function returns error:<http_code> as last line of response
#
#     test_and_remove_http_code: if response param is empty, the response is read from the 
#     temp file /tmp/$$.tmp. This allows processing large API response such as TCI/apps  
#
#   Version 1.1.0 - 2023/10/13 - Pierre Ayel
#     test_and_remove_http_code: stores the latest HTTP code into the variable HTTP_CODE
#     so it can be retrieved in other script parts
#
################################################################################

readonly NOT_FOUND="NOT_FOUND"
export NOT_FOUND

################################################################################
# Prints message to stderr.
# When stdout is used to pass value back from function, it cannot be used to print a log statement.

function echoerr() {
  echo "$@" 1>&2
}

################################################################################
# Tests the value of HTTP response code that is passed as a last line in HTTP response
# If test passes, response is returned without the HTTP response code
#
# If response param is empty, the response is read from the temp file /tmp/$$.tmp

function test_and_remove_http_code() {
  
  local expected_http_code="${1}"
  local response="${2}"
  local noexit=""
  [ "$#" -ge 3 ] && noexit="${3}"
  
  local http_code=""
  if [ "${response}" = "" ] ; then
  	http_code=$(tail -n 1 "/tmp/$$.tmp")
  	
  	if [[ "${http_code}" != "${expected_http_code}" ]]; then
  	    response=$(cat "/tmp/$$.tmp")
  	    
	    echoerr "Expected HTTP ${expected_http_code} but got HTTP ${http_code}: response=${response}"
	    if [ "${noexit}" = "" ] ; then
	      echoerr "Exiting ..."
	      exit 1
	    fi  
	fi
        head -n -1 "/tmp/$$.tmp"
  else
  	http_code=$(tail -n 1 <<<"${response}")
  	
  	if [[ "${http_code}" != "${expected_http_code}" ]] ; then
	    echoerr "Expected HTTP ${expected_http_code} but got HTTP ${http_code}: response=${response}"
	    if [ "${noexit}" = "" ] ; then
	      echoerr "Exiting ..."
	      exit 1
	    fi  
	fi
        head -n -1 <<<"${response}"
  fi
  
  if [[ "${http_code}" != "${expected_http_code}" ]] ; then
  	echo error:${http_code}
  fi
}

################################################################################
# Removes CR and LF from string
function remove_cr_lf() {

  local input="${1}"
  echo "${input}" | tr -d '\n\r'
}

function get_vault_token() {

  echoerr "Getting vault token"
  VAULT_TOKEN="$(vault write -field=token auth/gitlab-jwt/login role="${VAULT_ROLE_NAME}" jwt="${CI_JOB_JWT}")"
  export VAULT_TOKEN
  echoerr "Got vault token"
}

# Translates cicd environment to vault environment
function get_vault_environment() {

  local environment="${1}"

  case "${environment}" in
  'sandbox' | 'dev') echo "development" ;;
  'tst') echo "test" ;;
  'acc') echo "acceptance" ;;
  'prd') echo "production" ;;
  *)
    echoerr "Unknown environment ${environment}"
    exit 1
    ;;
  esac
}

function get_vault_secret() {

  local path="${1}"

  local environment
  environment="$(get_vault_environment "${CI_ENVIRONMENT_NAME}")"

  local workload
  workload="/workload/$(echo "${CI_PROJECT_PATH}" | cut -d/ -f2)"
  path="${workload}/${environment}/${path}"

  echoerr "Getting secret ${path}"
  vault kv get -format=json "${path}"
  echoerr "Got secret ${path}"
}

function put_vault_secret() {

  local path="${1}"
  local value="${2}"

  local environment
  environment="$(get_vault_environment "${CI_ENVIRONMENT_NAME}")"

  local workload
  workload="/workload/$(echo "${CI_PROJECT_PATH}" | cut -d/ -f2)"
  path="${workload}/${environment}/${path}"

  local tmp_file
  tmp_file="$(mktemp)"

  cat <<<"${value}" >"${tmp_file}"
  echoerr "Putting secret ${path}"
  vault kv put -format=json "${path}" @"${tmp_file}"
  echoerr "Put secret ${path}"
  rm -rf "${tmp_file}"
}

function render_organization_name() {
  # if NGI_BUSINESSSCOPE is set and not empty print hyphen after NGI_BUSINESSSCOPE
  # if NGI_BUSINESSDOMAIN is set and  not empty print hyphen before NGI_BUSINESSDOMAIN
  echo "${NGI_BUSINESSSCOPE}${NGI_BUSINESSSCOPE:+-}${CI_ENVIRONMENT_NAME}${NGI_BUSINESSDOMAIN:+-}${NGI_BUSINESSDOMAIN}"
}

# Convert string to lower case
function to_lower_case() {

  local input="${1}"
  echo "${input,,}"
}

# Convert string to upper case
function to_upper_case() {

  local input="${1}"
  echo "${input^^}"
}

# Remove spaces
function remove_spaces() {

  local input="${1}"
  echo "${input// /}"
}

# Remove curly braces
function remove_curly_braces() {

  local input="${1}"
  tr -d '{}' <<<"${input}"
}

# Convert forward slash to hyphen
function forward_slash_to_hyphen() {

  local input="${1}"
  tr '/' '-' <<<"${input}"
}

# Filter out commented and empty lines
function filter_file() {

  local input_path="${1}"
  local output_path="${2:-/dev/stdout}"

  grep -v '^\s*$\|^\s*\#' "${input_path}" >"${output_path}"
}

# Filter out first line, commented out and empty lines of an CSV file
function filter_csv_file() {

  local input_path="${1:-/dev/stdin}"

  filter_file "${input_path}" | tail -n +2
}

# Validate unique constraint of records in a CSV file
# Fields argument is a comma separated string of column numbers as they appear in CSV file
function validate_unique_constraint_in_csv_file() {

  local fields="${1}"
  local input_path="${2:-/dev/stdin}"
  echoerr "Validating unique constraints in ${input_path}"

  # grep returns 1 when there is no match so we need to catch it and return 0
  local filtered_input
  filtered_input="$(grep "${DESIRED_STATE_PRESENT}" "${input_path}" || true)"

  # print declared fields, sort them using field separator, report unique counts, print only lines where count is greater than 1
  local duplicate_records
  duplicate_records="$(cut -d',' -f"${fields}" <<<"${filtered_input}" | sort --field-separator=',' | uniq -c | awk '$1 > 1 {print}')"

  if [[ -n "${duplicate_records}" ]]; then
    echoerr "Unique constraint violation in ${input_path}:"
    echoerr "${duplicate_records}"
    echoerr "Exiting ..."
    exit 1
  fi
  echoerr "Validated unique constraints in ${input_path}"
}

# Get pom element value
function get_pom_element_value() {

  local element_name="${1}"
  local pom_file_path="${CI_PROJECT_DIR}/${CICD_BUILD_DIR}/pom.xml"

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
function get_pom_element_group_id() {
  get_pom_element_value "groupId"
}

# Convenience function
function get_pom_element_artifact_id() {
  get_pom_element_value "artifactId"
}

# Convenience function
function get_pom_element_version() {
  get_pom_element_value "version"
}

# Render request body from template_dir, template_file and environment variables
function render_request_body() {
	set -x
	
  local template_dir="${1}"
  local template_file="${2}"
  local template_file_path="${CI_PROJECT_DIR}/${CICD_TMP_DIR}/${template_dir}/${template_file}"

  echoerr "Rendering template file ${template_file}"
  
  cat "${template_file_path}" | envsubst | tee "/tmp/${template_file}"
  ####envsubst <"${template_file_path}" | jq | tee "/tmp/${template_file}"
}

##################################################################################################
# orig-filename: ./gitlab-scripts/commonScripts.sh

function echolog() {
  echo "***" "$@"
}

function separatelog() {
  echoerr "********************************************************************************"
}

function read_pom_info() {
  echolog "Reading information from POM"
  APPLICATION_NAME=$(get_pom_value artifactId)
  test_value_exists "ApplicationName" "$APPLICATION_NAME"
  echolog "ApplicationName=$APPLICATION_NAME"

  GROUP_ID=$(get_pom_value groupId)
  test_value_exists "GroupId" "$GROUP_ID"
  echolog "GroupId=$GROUP_ID"

  APPLICATION_VERSION=$(get_pom_value version)
  test_value_exists "ApplicationVersion" "$APPLICATION_VERSION"
  echolog "ApplicationVersion: $APPLICATION_VERSION"
}

function test_value_exists() {
  if [[ "$2" == "" ]]; then
    echoerr "No such value: $1"
    exit 1
  fi
}

function get_pom_value() {
  POMFILE=${POM_FILE_PATH:-${CI_PROJECT_DIR}/${CICD_BUILD_DIR}/pom.xml}
  echoerr "POM_FILE_PATH=${POM_FILE_PATH}"
  echoerr "POMFILE=${POMFILE}"

  VALUE=$(xmlstarlet sel -t -v "count(/_:project/*[local-name() = '$1'])" $POMFILE)
  if [[ $VALUE -eq 1 ]]; then
    xmlstarlet sel -t -v "/_:project/*[local-name() = '$1']" $POMFILE
  else
    PARENT=$(xmlstarlet sel -t -v "/_:project/_:parent/_:relativePath" $POMFILE)
    if [[ "$PARENT" != "" ]]; then
      PARENTPOM=$(dirname $POMFILE)/$PARENT/pom.xml
      xmlstarlet sel -t -v "/_:project/*[local-name() = '$1']" $PARENTPOM
    fi
  fi
}
