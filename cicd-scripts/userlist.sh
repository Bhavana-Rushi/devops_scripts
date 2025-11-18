
#!/bin/bash
TOKEN=$1
ORG="Sanofi-CHC"
RESULTS_FILE="user_list.txt"
page=1
per_page=100
total_pages=10
user_list=""
while [[ $page -le $total_pages ]]; do
    response=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/orgs/$ORG/members?per_page=$per_page&page=$page")
    users=$(echo "$response" | jq -r '.[].login')
    user_list+="$users"$'\n'
    total_users=$(echo "$response" | jq -r '. | length')
    if [[ $total_users -lt $per_page ]]; then
        break
    fi
    ((page++))
done
echo "$user_list" > "$RESULTS_FILE"
cat user_list.txt
