
import os
import csv
import subprocess
import shutil
import sys

def process_repo(repo_name):
    os.chdir(workspace)
    checkout_repository(repo_name)
    os.chdir(repo_name)
    subprocess.run(["git", "checkout", "main"])
    update_codeowners(workspace, repo_name, "main")
  #  subprocess.run(["git", "checkout", "development"])
  #  update_codeowners(workspace, repo_name, "development")

def checkout_repository(repo_name: str):
    source_repo_url = f"https://{github_token}:x-oauth-basic@github.com/{org_name}/{repo_name}.git"
    subprocess.run(["git", "clone", source_repo_url])

def update_codeowners(workspace, repo_name, branch):
    dest_folder = os.path.join(workspace, repo_name, ".github")
    os.makedirs(dest_folder, exist_ok=True)
    shutil.copy2(codeowners_file_path, os.path.join(dest_folder, "CODEOWNERS"))
    subprocess.run(["git", "add", os.path.join(dest_folder, "CODEOWNERS")])
    subprocess.run(["git", "commit", "-m", f"Add CODEOWNERS on {branch} branch"])
    subprocess.run(["git", "pull", "origin", "main", "--rebase"])
    subprocess.run(["git", "push", "origin", branch])

if __name__ == "__main__":
    org_name = sys.argv[1]
    github_token = sys.argv[2]
    repos_file = sys.argv[3]
    workspace = sys.argv[4]
    codeowners_file_path = sys.argv[5]
    git_email = sys.argv[6]
    git_username = sys.argv[7]

    subprocess.run(["git", "config", "--global", "user.email", git_email])
    subprocess.run(["git", "config", "--global", "user.name", git_username])

    with open(repos_file, newline='') as repos_file:
        repo_reader = csv.reader(repos_file)
        next(repo_reader)

        repo_names = list(repo_reader)

        for repo_row in repo_names:
            if len(repo_row) >= 2:
                repo_name = repo_row[0].strip()
                print("Processing Repo:", repo_name)
                process_repo(repo_name)
            else:
                print(f"Skipping invalid repo row: {repo_row}")

    print("All repositories processed successfully.")
