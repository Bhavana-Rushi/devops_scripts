
#!/bin/bash

# Parse Options
while (( "$#" )); do
  case "$1" in
    -d | --debug ) # process option a
      IS_DEBUG=true
      shift
      ;;
    -u|--username)
      GITHUB_USERNAME=$2
      shift 2
      ;;
    -t|--token)
      GITHUB_TOKEN=$2
      shift 2
      ;;
    -* )
      shift
      break
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

##################################################
# Set positional arguments in their proper place #
##################################################
eval set -- "$PARAMS"

# Variables
organization=$1
filename=$2

echo "organization: $organization"
echo "filename: $filename"

debug () {
    if [[ ${IS_DEBUG} ]]; then
    echo "$1"
    fi
}

while IFS=, read -r new_repo_name readonlyteam
do
    #new_repo_description=${new_repo_description//[$'\t\r\n']} && new_repo_description=${new_repo_description%%*( )}
    new_repo_name=${new_repo_name//[$'\t\r\n']} && new_repo_name=${new_repo_name%%*( )}

    echo "new_repo_name: $new_repo_name"
    #echo "new_repo_description: $new_repo_description"
    echo "readonlyteam: $readonlyteam"
    #echo "readonlyteam2: $readonlyteam2"

    # Error Handling - Verify GITHUB_USERNAME and GITHUB_TOKEN have been set
    if [[ -z ${GITHUB_USERNAME} ]] || [[ -z ${GITHUB_TOKEN} ]]; then
    echo 'ERROR: You must set both GITHUB_USERNAME and GITHUB_TOKEN prior to running.'
    echo '  - Ex: export GITHUB_USERNAME=Octocat'
    echo '  - Ex: export GITHUB_TOKEN=abc123def456'

    debug 'Exiting script.'

    exit 1
    fi

    # Set api_domain and new_repo_url based on if ghe_domain has been set to handle sending
    # to both GHE and GitHub.com depending on use case
    api_domain='https://api.github.com/'
    if [[ -n "$GHE_DOMAIN" ]]; then
        api_domain="$GHE_DOMAIN/api/v3/"
    fi

    # Assign readonly team 
    debug "Assigning read-only team1 to repo ${new_repo_name}"

    assign_readonly_team_response=$(curl --write-out '%{http_code}' --silent --output /dev/null \
          -H 'authorization: Bearer '"${GITHUB_TOKEN}" \
          -X PUT \
          "${api_domain}orgs/${organization}/teams/${readonlyteam}/repos/${organization}/${new_repo_name}" -d '{"permission":"pull"}')

    debug "ASSIGN READONLY team response code= $assign_readonly_team_response"

    # Error Handling
    if [[ "${assign_readonly_team_response}" -ne '204' ]]; then
      echo 'ERROR: Failed to assign read-only team to repository'
      debug "$assign_readonly_team_response"
      debug 'Exiting script.'
      exit 1
    fi
done < "${filename}"
