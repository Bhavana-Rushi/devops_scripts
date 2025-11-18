
import os
import sys
import subprocess
import requests
import shlex

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

def perform_action(appname, tci_token, workspace):
    try:
        os.chdir(f"{workspace}/chc_scripts/cicd-scripts")
        subprocess.run("chmod 777 tibcli", shell=True, check=True)
        subprocess.run(f"./tibcli authorize --token {shlex.quote(tci_token)}", shell=True, check=True)

        configure_cmd = (
            f'./tibcli app configure {shlex.quote(appname)} '
            '--engineVar "BW_JAVA_OPTS=--add-exports=java.base/sun.security.ssl=ALL-UNNAMED" '
            '--engineVar "java.property.com.tibco.tibjms.connect.attemptcount=10" '
            '--engineVar "java.property.com.tibco.tibjms.connect.attemptdelay=20000" '
            '--engineVar "java.property.com.tibco.tibjms.connect.attempttimeout=45000" '
            '--engineVar "java.property.com.tibco.tibjms.reconnect.attemptcount=10" '
            '--engineVar "java.property.com.tibco.tibjms.reconnect.attemptdelay=20000" '
            '--engineVar "java.property.com.tibco.tibjms.reconnect.attempttimeout=45000"'
        )
        subprocess.run(configure_cmd, shell=True, check=True, input=b"yes\n")
        print("✅ App configuration successful.")
    except subprocess.CalledProcessError as e:
        print(f"❌ Command failed: {e}")
        exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 tibco_configure.py <appname>")
        exit(1)

    appname = sys.argv[1]
    client_id = os.getenv("CIC_TCI_CLIENTID_CICD")
    client_secret = os.getenv("CIC_TCI_CLIENTSECRET_CICD")
    workspace = os.getenv("UNIQUE_WORKSPACE")

    if not all([client_id, client_secret, workspace]):
        print("❌ One or more required environment variables are missing.")
        exit(1)

    token = get_tci_token(client_id, client_secret)
    if token:
        perform_action(appname, token, workspace)
