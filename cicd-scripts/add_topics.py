
import requests
import sys
import csv

# Set your GitHub token and organization name
org_name = sys.argv[1]
github_token = sys.argv[2]
repos_file = sys.argv[3]

def update_repo_topics(repo_name: str, topics: list):
    url = f"https://api.github.com/repos/{org_name}/{repo_name}/topics"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.mercy-preview+json",  # Use preview header for topics API
        "Content-Type": "application/json"
    }
    data = {
        "names": topics
    }
    response = requests.put(url, headers=headers, json=data)
    if response.status_code == 200:
        print(f"Topics updated for '{repo_name}' repository.")
    else:
        print(f"Failed to update topics for '{repo_name}' repository. Error: {response.text}")

# Read repository names from the provided CSV file
with open(repos_file, newline='') as repos_file:
    repo_reader = csv.reader(repos_file)
    next(repo_reader)  

    repo_names = list(repo_reader)

# Loop through each repository and update its topics
for repo_row in repo_names:
    if len(repo_row) >= 2:
        repo_name = repo_row[0].strip()
        topics = ["cc-F5A3111056"]  # Replace with your desired topics
        update_repo_topics(repo_name, topics)
    else:
        print(f"Skipping invalid repo row: {repo_row}")

print("Finished updating topics for all repositories.")
