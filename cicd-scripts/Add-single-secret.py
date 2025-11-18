
import sys
import csv
import requests
import json
from base64 import b64encode
from nacl import encoding, public

def encrypt(public_key: str, secret_value: str) -> str:
    public_key = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
    sealed_box = public.SealedBox(public_key)
    encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
    return b64encode(encrypted).decode("utf-8")

def create_or_update_secret(public_key: str, secret_value: str, org_name: str, repo_name: str, secret_name: str, github_token: str, key_id: str, encrypted_value: str):
    url = f"https://api.github.com/repos/{org_name}/{repo_name}/actions/secrets/{secret_name}"
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {github_token}",
        "X-GitHub-Api-Version": "2022-11-28"
    }
    data = {
        "encrypted_value": encrypted_value,
        "key_id": str(key_id)
    }
    response = requests.put(url, headers=headers, data=json.dumps(data))
    if response.status_code == 201:
        print(f"Secret {secret_name} added in {repo_name}")
    elif response.status_code == 204:
        print(f"Secret {secret_name} updated in {repo_name}")
    else:
        print(f"Failed to create/update secret {secret_name} in {repo_name}. Response: {response.status_code}")
        print(response.text)

if __name__ == "__main__":
    org_name = sys.argv[1]
    github_token = sys.argv[2]
    repos_file = sys.argv[3]

    with open(repos_file, newline='') as repos_file:
        repo_reader = csv.reader(repos_file)
        next(repo_reader)

        repo_names = list(repo_reader)

    print("Repo Names:", repo_names)

    secrets = {
        "PROD_TCM_TCI_CLIENT_ID": sys.argv[4], 
        "PROD_TCM_TCI_CLIENT_SECRET": sys.argv[5],
    }

    for repo_row in repo_names:
        if len(repo_row) >= 2:
            repo_name = repo_row[0].strip()

            print("Processing Repo:", repo_name)

            public_key_url = f"https://api.github.com/repos/{org_name}/{repo_name}/actions/secrets/public-key"
            headers = {
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {github_token}",
                "X-GitHub-Api-Version": "2022-11-28"
            }
            response = requests.get(public_key_url, headers=headers)

            if response.status_code == 200:
                key_data = response.json()
                public_key = key_data["key"]
                key_id = key_data["key_id"]

                for secret_name, secret_value in secrets.items():
                    if len(secret_value) >= 1:
                        encrypted_value = encrypt(public_key, secret_value)
                        create_or_update_secret(public_key, secret_value, org_name, repo_name, secret_name, github_token, key_id, encrypted_value)
                    else:
                        print(f"Skipping invalid secret value: {secret_name}")
            else:
                print(f"Failed to fetch public key for repository: {repo_name}")
        else:
            print(f"Skipping invalid repo row: {repo_row}")
    print("Finished processing all repositories and secrets.")
