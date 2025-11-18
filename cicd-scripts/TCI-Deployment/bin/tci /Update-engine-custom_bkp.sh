
#!/bin/bash

# Function to perform action with status check and retries
perform_action() {
    local appname=$1
    local TCI_TOKEN=$2
    local properties_file=$3

    # Change to the working directory
    cd "${UNIQUE_WORKSPACE}/chc_scripts/cicd-scripts" || { echo "Failed to change directory"; exit 1; }

    # Run the tibcli command with necessary permissions
    sudo su
    cd "${UNIQUE_WORKSPACE}/chc_scripts/cicd-scripts"
    chmod 777 tibcli

    # Authorize with the TCI token
    if ! ./tibcli authorize --token "${TCI_TOKEN}"; then
        echo "Authorization failed."
        exit 1
    fi

    # Prepare engine variable arguments
    local engine_vars=()

    # Read properties from the .properties file
    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)  # Trim whitespace
        value=$(echo "$value" | xargs)  # Trim whitespace
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key || -z $value ]] && continue
        engine_vars+=("--engineVar" "${key}=${value}")
    done < "$properties_file"

    # Check if engine_vars is empty
    if [ ${#engine_vars[@]} -eq 0 ]; then
        echo "No engine variables found in properties file."
        exit 1
    fi

    # Debugging output
    echo "Running tibcli command with the following engine variables:"
    printf '%s\n' "${engine_vars[@]}"

    # Build the command as a string
    local command="./tibcli app configure ${appname}"
    for var in "${engine_vars[@]}"; do
        command+=" $var"
    done

    # Log the final command
    echo "Final command: yes | $command"

    # Execute the command
    eval "yes | $command"

    # Check the status of the command
    if [ $? -ne 0 ]; then
        echo 'tibcli command failed'
        exit 1
    fi

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
http_code=$(echo "$response" | tail -n1)

# Check if the HTTP response code is 200
if [ "$http_code" -ne 200 ]; then
    echo "Failed to get token. HTTP Response Code: $http_code"
    echo "Response: $json_response"
    exit 1
fi

# Extract the token
TCI_TOKEN=$(echo "$json_response" | jq -r '.access_token')

# Check if the token was extracted successfully
if [ "$TCI_TOKEN" == "null" ] || [ -z "$TCI_TOKEN" ]; then
    echo "Failed to extract access token from the response."
    echo "Response: $json_response"
    exit 1
fi

# Example usage of the function
# properties_file="path/to/your/properties_file.properties" # Update with your properties file path
perform_action "$1" "$TCI_TOKEN" "$2"
