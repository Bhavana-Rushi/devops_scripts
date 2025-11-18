
import sys
import csv
import requests
import json

# Set your GitHub token and organization name
org_name = sys.argv[1]
github_token = sys.argv[2]
repos_file = sys.argv[3]

def check_env_protection(repo_name, env_name):
    url = f"https://api.github.com/repos/{org_name}/{repo_name}/environments/{env_name}"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.v3+json"
    }

    response = requests.get(url, headers=headers)
    return response.status_code, response.json()

def add_environment_setting(repo_name: str, env_name: str):
    url = f"https://api.github.com/repos/{org_name}/{repo_name}/environments/{env_name}"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.ant-man-preview+json",  # Using preview header for environments API
        "Content-Type": "application/json"
    }
    data = {
        "wait_timer": 30,
        "prevent_self_review": False,
        "reviewers": [
            {"type": "Team", "id": 8431934}
        ],
        "deployment_branch_policy": {
            "protected_branches": False,
            "custom_branch_policies": True
        }
    }
    response = requests.put(url, headers=headers, json=data)
    if response.status_code == 200:
        print(f"Production environment updated for '{repo_name}' repository.")
    else:
        print(f"Failed to update production environment for '{repo_name}' repository. Error: {response.text}")

def check_and_create_env_protection_rules(repo_name):
    env_to_protect = ["prod", "uat"]
    for env_name in env_to_protect:
        #status_code, response_json = check_env_protection(repo_name, env_name)
        #if status_code == 200:
        #    print(f"env protection rules for '{env_name}' branch of '{repo_name}' are already in place.")
        #elif status_code == 404:
        #    add_branch_protection(repo_name, env_name)
        #else:
        #    print(f"Failed to check branch protection for '{env_name}' branch of '{repo_name}'. Error: {response_json}")
       add_environment_setting(repo_name, env_name)

with open(repos_file, newline='') as repos_file:
    repo_reader = csv.reader(repos_file)
    next(repo_reader)  

    repo_names = list(repo_reader)

for repo_row in repo_names:
    if len(repo_row) >= 2:
        repo_name = repo_row[0].strip()
        check_and_create_env_protection_rules(repo_name)
    else:
        print(f"Skipping invalid repo row: {repo_row}")

print("Finished checking and creating environment setting for all repositories.")
