
import sys
import csv
import requests
import json

# Set your GitHub token and organization name
org_name = sys.argv[1]
github_token = sys.argv[2]
repos_file = sys.argv[3]

def check_branch_protection(repo_name, branch_name):
    url = f"https://api.github.com/repos/{org_name}/{repo_name}/branches/{branch_name}/protection"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.v3+json"
    }

    response = requests.get(url, headers=headers)
    return response.status_code, response.json()

# Function to add branch protection rules
def add_branch_protection(repo_name: str, branch_name: str)-> str:
    url = f"https://api.github.com/repos/{org_name}/{repo_name}/branches/{branch_name}/protection"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.v3+json"
    }
    data = {
        "required_status_checks": {
            "strict": True,
            "contexts": []
        },
        "enforce_admins": True,
        "required_pull_request_reviews": {
            "dismissal_restrictions": {
                "users": [
                ],
                "teams": [
                    "Opella-TCI-AIMS-Support",
                    "Opella-TCI-AMS-Support",
                    "Opella-TCI-Codeowners",
                    "CHC-Accenture-developers"
                ]
            },
            "dismiss_stale_reviews": False,
            "require_code_owner_reviews": True,
            "required_approving_review_count": 1,
            "require_last_push_approval": False,
            "bypass_pull_request_allowances": {
                "users": [
                ],
                "teams": [
                    "Opella-TCI-AIMS-Support",
                    "Opella-TCI-AMS-Support",
                    "Opella-TCI-Codeowners",
                    "CHC-Accenture-developers"
                ]
            }
        },
        "restrictions": {
            "users": [
            ],
            "teams": [
                "Opella-TCI-AIMS-Support",
                "Opella-TCI-AMS-Support",
                "Opella-TCI-Codeowners",
                "CHC-Accenture-developers"
            ]
        },
        "required_linear_history": True,
        "allow_force_pushes": False,
        "allow_deletions": False,
        "block_creations": False,
        "required_conversation_resolution": True,
        "lock_branch": False
    }
    response = requests.put(url, headers=headers, json=data)
    if response.status_code == 200:
        print(f"Branch protection added to '{branch_name}' branch of '{repo_name}'.")
    else:
        print(f"Failed to add branch protection to '{branch_name}' branch of '{repo_name}'. Error: {response.text}")

def check_and_create_protection_rules(repo_name):
    branches_to_protect = ["main", "development"]
    for branch_name in branches_to_protect:
        status_code, response_json = check_branch_protection(repo_name, branch_name)
        if status_code == 200:
          #  print(f"Branch protection rules for '{branch_name}' branch of '{repo_name}' are already in place.") 
          # added this to update protection policy without deleting it 19/6
            add_branch_protection(repo_name, branch_name)
        elif status_code == 404:
            add_branch_protection(repo_name, branch_name)
        else:
            print(f"Failed to check branch protection for '{branch_name}' branch of '{repo_name}'. Error: {response_json}")

with open(repos_file, newline='') as repos_file:
        repo_reader = csv.reader(repos_file)
        next(repo_reader)  

        repo_names = list(repo_reader)

for repo_row in repo_names:
    if len(repo_row) >= 2:
        repo_name = repo_row[0].strip()
        check_and_create_protection_rules(repo_name)
    else:
        print(f"Skipping invalid repo row: {repo_row}")

print("Finished checking and creating branch protection for all repositories.")

