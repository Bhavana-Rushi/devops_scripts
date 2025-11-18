
#!/bin/bash

# Source the script containing the get_tci_token function
#source "${DIRSCRIPT}/chc-functions.sh"

# Function to perform action with status check and retries
perform_action() {
    local appname=$1
    local TCI_TOKEN=$2

    # Change to the working directory
    cd "${WORKSPACE}/chc_scripts/cicd-scripts" || { echo "Failed to change directory"; exit 1; }

    # Run the tibcli command with necessary permissions
    sudo su
    cd '${WORKSPACE}/chc_scripts/cicd-scripts'
    chmod 777 tibcli
    ./tibcli authorize --token ${TCI_TOKEN}

    yes | ./tibcli app configure ${appname} \
        --engineVar CUSTOM_ENGINE_PROPERTY1=com.tibco.tibjms.connect.attemptcount=20 \
        --engineVar CUSTOM_ENGINE_PROPERTY2=com.tibco.tibjms.connect.attemptdelay=1000 \
        --engineVar CUSTOM_ENGINE_PROPERTY3=com.tibco.tibjms.connect.attempttimeout=1000 \
        --engineVar CUSTOM_ENGINE_PROPERTY4=com.tibco.tibjms.reconnect.attemptcount=600 \
        --engineVar CUSTOM_ENGINE_PROPERTY5=com.tibco.tibjms.reconnect.attemptdelay=1000 \
        --engineVar CUSTOM_ENGINE_PROPERTY6=com.tibco.tibjms.reconnect.attempttimeout=1000

    # Check the status of the command
    if [ $? -ne 0 ]; then
        echo 'tibcli command failed'
        exit 1
    fi

    # Return to the original directory
    cd - || { echo "Failed to return to the original directory"; exit 1; }
}

# get the token
response="$(
            curl -sS -w "\n%{http_code}" \
            "https://eu.account.cloud.tibco.com/idm/v1/oauth2/token" \
            --header "Content-Type: application/x-www-form-urlencoded" \
            --data "grant_type=client_credentials&scope=TCI&client_id=$CIC_TCI_CLIENTID_CICD&client_secret=$CIC_TCI_CLIENTSECRET_CICD"
            )"
          json_response=$(echo $response | sed 's/ [0-9]\+$//')
          TCI_TOKEN=$(echo $json_response | jq -r '.access_token')
# Example usage of the function
perform_action "$1" "$TCI_TOKEN"
