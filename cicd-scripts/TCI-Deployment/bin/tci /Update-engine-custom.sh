#!/bin/bash

# Source the script containing the get_tci_token function
# source "${DIRSCRIPT}/chc-functions.sh"

# Function to perform action with status check and retries
perform_action() {
    local appname="$1"
    local TCI_TOKEN="$2"
    local script_dir="${UNIQUE_WORKSPACE}/chc_scripts/cicd-scripts"
    #local script_dir="${WORKSPACE}/chc_scripts/cicd-scripts"
    local engine_properties="$3"

    # Change to the working directory
    sudo su
    cd "$script_dir" || { echo "Failed to change directory to $script_dir"; exit 1; }

    # Ensure tibcli is executable
    chmod 777 tibcli || { echo "Failed to change permissions on tibcli"; exit 1; }

    # Run the tibcli command with necessary permissions
    ./tibcli authorize --token "$TCI_TOKEN" || { echo 'tibcli authorization failed'; exit 1; }

    # Read the property file line by line
    while IFS= read -r line; do
        line=$(echo "$line" | xargs)  # Trim leading/trailing whitespace
        # Ignore lines starting with # and blank lines
        if [[ ! $line =~ ^# ]] && [[ -n $line ]]; then
            # Extract the property name and value
            property_name=$(echo "$line" | cut -d'=' -f1)
            property_value=$(echo "$line" | cut -d'=' -f2-)
            echo "$property_name" "$property_value"

            # Update the engine property
            yes | ./tibcli app configure "$appname" --engineVar "$property_name=$property_value" || { echo "Failed to configure $property_name"; exit 1; }
        fi
    done < "$engine_properties"

    # Return to the original directory
    cd - || { echo "Failed to return to the original directory"; exit 1; }
}

# Get the token
response="$(
    curl -sS -w "\n%{http_code}" \
    "https://eu.account.cloud.tibco.com/idm/v1/oauth2/token" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data "grant_type=client_credentials&scope=TCI&client_id=$CIC_TCI_CLIENTID_CICD&client_secret=$CIC_TCI_CLIENTSECRET_CICD"
)"
json_response=$(echo "$response" | sed 's/ [0-9]\+$//')
TCI_TOKEN=$(echo "$json_response" | jq -r '.access_token')

# Example usage of the function, passing the property file
perform_action "$1" "$3" "$2"
