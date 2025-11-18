
#!/bin/bash
TOKEN=$1
ORG="Sanofi-GitHub"
RESULTS_FILE="repo_list.txt"
Team_Group="CHC-developers"
page=1
per_page=100
total_pages=20
repo_list=""
while [[ $page -le $total_pages ]]; do
    #response=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/orgs/$ORG/repos?per_page=$per_page&page=$page&type=private")
    response=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/orgs/$ORG/teams/$Team_Group/repos?per_page=$per_page&page=$page&type=private")
    repos=$(echo "$response" | jq -r '.[].name')
    repo_list+="$repos"$'\n'
    total_repos=$(echo "$response" | jq -r '. | length')
    if [[ $total_repos -lt $per_page ]]; then
        break
    fi
    ((page++))
done
echo "$repo_list" > "$RESULTS_FILE"
cat repo_list.txt
