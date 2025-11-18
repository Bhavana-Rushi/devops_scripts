
#!/bin/bash
set -ex

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)
    case "$KEY" in
            -application_file)             application_file=${VALUE} ;;
            -sharedmodule_file)            sharedmodule_file=${VALUE} ;;
            
            *)
    esac
done

# Array to store keys from dev.properties(application property file)
declare -a dev_keys

# Read dev.properties file and extract keys
while IFS='=' read -r key _ || [[ -n "$key" ]]
do
  if [[ -n "$key" ]]; then
    dev_keys+=("$key")
  fi
done < <(tail -n +2 ${application_file})

updated_file="updated_app.properties"

# Loop through the keys and process each one
for key in "${dev_keys[@]}"
do
  # Search for the key in sharedmodule.properties
  value=$(grep -E "^$key=" ${sharedmodule_file} | cut -d'=' -f2-)
  
  # If key exists in sharedmodule.properties, use its value
  # Otherwise, use the value from dev.properties
  if [[ -n "$value" ]]; then
    echo "$key=$value" >> "$updated_file"
  else
    line=$(grep -E "^$key=" ${application_file})
    echo "$line" >> "$updated_file"
  fi
done

rm ${application_file}
mv ${updated_file} ${application_file}
