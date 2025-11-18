
import requests
import os
import shutil
import subprocess
import csv
import json
import base64
import sys
import yaml
import ruamel.yaml

def check_branch_exists(repo_name: str, branch_name: str) -> bool:
    url = f"https://api.github.com/repos/{org_name}/{repo_name}/branches/{branch_name}"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.v3+json"
    }

    response = requests.get(url, headers=headers)
    return response.status_code == 200

def create_branch(repo_name: str, branch_name: str, source_branch: str):
    os.chdir(os.path.join(workspace, repo_name))
    subprocess.run(["git", "checkout", source_branch])
    subprocess.run(["git", "checkout", "-b", branch_name])
    subprocess.run(["git", "pull", "origin", "main", "--rebase"])
    subprocess.run(["git", "push", "origin", branch_name])
    
def checkout_repository(source_repo_name: str):
    source_repo_url = f"https://{github_token}:x-oauth-basic@github.com/{org_name}/{repo_name}.git"
    subprocess.run(["git", "clone", source_repo_url])
    
def create_workflows(repo_name:str):
    os.chdir(workspace)
    workflow_path = os.path.join(workspace, "calling-workflows")
    destination_repo_path = os.path.join(workspace, repo_name)
    dest_workflow_path = os.path.join(destination_repo_path, ".github", "workflows")

    os.makedirs(dest_workflow_path, exist_ok=True)

    for workflow_file in ["TCI-DEV.yml", "TCI-SIT.yml", "TCI-UAT.yml", "TCI-PROD.yml"]:
        source_file_path = os.path.join(workflow_path, workflow_file)
        dest_file_path = os.path.join(dest_workflow_path, workflow_file)
        shutil.copy2(source_file_path, dest_file_path)
        print(f"copying {source_file_path} to {dest_file_path}")
        try:
            yaml = ruamel.yaml.YAML()
            with open(dest_file_path, 'r') as file:
                data = yaml.load(file)
                file_name = workflow_file.split('.yml')[0]
                data["jobs"][file_name]["with"]["INTERFACE_NAME"] = interface_name
       
            with open(dest_file_path, 'w') as file:
                yaml.dump(data, file)
        except EXCEPTION as e:
            print(f"Error occured whileprocessing {workflow_file}: {e}")

    os.chdir(os.path.join(workspace, repo_name))
    subprocess.run(["git", "add", "."])
    subprocess.run(["git", "commit", "-m", "Add TCI workflows"])
    subprocess.run(["git", "pull", "origin", "main", "--rebase"])
    subprocess.run(["git", "push", "origin", "main"])
    print(f"Workflows and CODEOWNERS file copied and committed successfully to the main branch of '{repo_name}'.")

if __name__ == "__main__":
    org_name = sys.argv[1]
    github_token = sys.argv[2]
    repos_file = sys.argv[3]
    workspace = sys.argv[4]
    git_email = sys.argv[5]
    git_username = sys.argv[6]

    subprocess.run(["git", "config", "--global", "user.email", git_email])
    subprocess.run(["git", "config", "--global", "user.name", git_username])

    print(f"Current Working Directory: {os.getcwd()}")

    with open(repos_file, newline='') as file:
        repo_reader = csv.reader(file)
        next(repo_reader)  

        repos = list(repo_reader)

        for repo_row in repos:
            if len(repo_row) >= 2:
                repo_name = repo_row[0].strip()
                interface_name = repo_row[1].strip()
            
            os.chdir(workspace)
            checkout_repository(repo_name)

            main_branch_exists = check_branch_exists(repo_name, "main")

            if main_branch_exists:

                workflow_path = os.path.join(workspace, repo_name, ".github", "workflows")
                
                workflows_present = os.path.exists(workflow_path)

                if workflows_present:

                    print(f"Deleting existing workflows in '{repo_name}'...")
                    shutil.rmtree(workflow_path)

                    create_workflows(repo_name)  

                if not workflows_present:

                    create_workflows(repo_name)   

                development_branch_exists = check_branch_exists(repo_name, "development")
                
                if not development_branch_exists:

                    create_branch(repo_name, "development", "main")

                    print(f"Development branch created successfully for '{repo_name}'.")   

                else:
                    print(f"Development branch already exists for '{repo_name}'.")

            else:
                print(f"Main branch is not present in '{repo_name}'.")
                os.chdir(os.path.join(workspace, repo_name))
                subprocess.run(["git", "branch", "-M", "main"])
                with open("readme.md", "w") as f:
                    f.write(repo_name)
                subprocess.run(["git", "add", "."])
                subprocess.run(["git", "commit", "-m", "added readme.md"])
                subprocess.run(["git", "pull", "origin", "main", "--rebase"])
                subprocess.run(["git", "push", "-u", "origin", "main"])
                print(f"Main branch created for '{repo_name}'.")
                create_workflows(repo_name) 
                create_branch(repo_name, "development", "main")
                print(f"Development branch created successfully for '{repo_name}'.")               
                
