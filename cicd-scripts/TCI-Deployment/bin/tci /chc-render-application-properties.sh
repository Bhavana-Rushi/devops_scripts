
#!/bin/bash
################################################################################
set -euo pipefail
set -o posix

typeset DIRSCRIPT=`dirname "${0}"`
DIRSCRIPT=`(cd "${DIRSCRIPT}" ; pwd)`

readonly SCRIPT=`basename "${0}"`

# Source cicd functions
# shellcheck disable=SC1090
source "${DIRSCRIPT}/../functions.sh"
# Source tcm functions
# shellcheck disable=SC1090
source "${DIRSCRIPT}/chc-functions.sh"

################################################################################

function main() {

  local application_properties_file_path="${1}"
  local application_properties_json_file_path="${2}"

  separatelog
  echoerr "application_properties_file_path=${application_properties_file_path}"
  echoerr "application_properties_json_file_path=${application_properties_json_file_path}"
  separatelog

  if ! [[ -f "${application_properties_file_path}" ]]; then
    echoerr "File ${application_properties_file_path} not found - omitting render application properties json ..."
  else
    filter_file "${application_properties_file_path}" |
      sed 's/\r//' |
      envsubst |
      sed -e 's/^\([^=]*\)=\(.*\)/\1====\2/' |
      jq --slurp --raw-input 'split("\n") | map(select(. !="")) | map(split("====") | { ("name"): .[0],"value":.[1] } )' \
        >"${application_properties_json_file_path}"
    echoerr "Rendered application properties json"
  fi
}

################################################################################

main "$@"

################################################################################
###  END OF FILE  ##############################################################
################################################################################
