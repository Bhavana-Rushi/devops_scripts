
import os
import sys
import subprocess
import requests

def get_tci_token(client_id, client_secret):
    url = "https://eu.account.cloud.tibco.com/idm/v1/oauth2/token"
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    data = {
        "grant_type": "client_credentials",
        "scope": "TCI",
        "client_id": client_id,
        "client_secret": client_secret
    }
    response = requests.post(url, headers=headers, data=data)
    if response.status_code == 200:
        return response.json().get("access_token")
    else:
        print("❌ Failed to retrieve token:", response.text)
        return None

def perform_action(appname, tci_token, workspace, properties_file):
    try:
        os.chdir(f"{workspace}/chc_scripts/cicd-scripts")
        subprocess.run(["chmod", "777", "tibcli"], check=True)
        subprocess.run(["./tibcli", "authorize", "--token", tci_token], check=True)

        # Prepare engine variable arguments
        engine_vars = []

        # Read properties from the .properties file
        with open(properties_file, 'r') as file:
            for line in file:
                line = line.strip()
                if line.startswith('#') or '=' not in line:
                    continue
                key, value = map(str.strip, line.split('=', 1))
                if key and value:
                    engine_vars.append(f"--engineVar {key}={value}")

        if not engine_vars:
            print("No engine variables found in properties file.")
            exit(1)

        print("Running tibcli command with the following engine variables:")
        for var in engine_vars:
            print(var)

        configure_cmd = ["./tibcli", "app", "configure", appname] + engine_vars
        print(f"Final command: {' '.join(configure_cmd)}")

        with subprocess.Popen(configure_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as proc:
            output, error = proc.communicate(b'y\n')
            if proc.returncode != 0:
                print("❌ tibcli command failed")
                print("Output:", output.decode())
                print("Error:", error.decode())
                exit(1)
            else:
                print("✅ App configuration successful.")
                print("Output:", output.decode())

    except subprocess.CalledProcessError as e:
        print(f"❌ Command failed: {e}")
        exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 tibco_configure.py <appname> <properties_file>")
        exit(1)

    appname = sys.argv[1]
    properties_file = sys.argv[2]
    client_id = os.getenv("CIC_TCI_CLIENTID_CICD")
    client_secret = os.getenv("CIC_TCI_CLIENTSECRET_CICD")
    workspace = os.getenv("UNIQUE_WORKSPACE")

    if not all([client_id, client_secret, workspace]):
        print("❌ One or more required environment variables are missing.")
        exit(1)

    token = get_tci_token(client_id, client_secret)
    if token:
        perform_action(appname, token, workspace, properties_file)
