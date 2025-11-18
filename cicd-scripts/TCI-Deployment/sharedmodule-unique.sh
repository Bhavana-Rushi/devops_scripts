
#!/bin/bash
set -ex

echo "checkout sharedmodule code"
config_file=$1
if [ ! -f  $config_file ]; then
    echo "No config file.Exiting"
    exit 1
fi
shared_modules_count=$(jq -r '.sharedmodules | length' "$config_file")
echo "shared module count is $shared_modules_count"
shared_modules=$(jq -r '.sharedmodules[]' "$config_file")
for ((index=0; index<$shared_modules_count; index++)); do
    repo_name=$(jq -r --argjson idx $index '.sharedmodules[$idx].repo_name' "$config_file")
    cd ${UNIQUE_WORKSPACE}/src/${INTERFACE_NAME}
    echo "checking out $repo_name repository"
    git clone -v -b development https://${GITHUB_PAT}:x-oauth-basic@github.com/Sanofi-GitHub/${repo_name}.git
    echo "update artifact-id and relative path in the pom.xml of sharedmodule"
    sharedmodule_path="${UNIQUE_WORKSPACE}/src/${INTERFACE_NAME}/$repo_name/src"
    directories=$(find "$sharedmodule_path" -mindepth 1 -maxdepth 1 -type d)
    for directory in $directories; do
        pom_file="${directory}/pom.xml"
        if [ -f "$pom_file" ]; then
            echo "pom.xml exists"
            artifact_id=$(xmlstarlet sel -t -v "//*[local-name()='parent']/*[local-name()='artifactId']" $pom_file)
            echo "existing artifactid is $artifact_id"
            relative_path=$(xmlstarlet sel -t -v "//*[local-name()='parent']/*[local-name()='relativePath']" $pom_file)
            echo "existing relative path is $relative_path"
            new_artifact_id="${INTERFACE_NAME}.application.parent"
            new_relative_path="../${INTERFACE_NAME}.application.parent"
            sed -i "s|<artifactId>${artifact_id}</artifactId>|<artifactId>${new_artifact_id}</artifactId>|g" "$pom_file"
            sed -i "s|<relativePath>${relative_path}</relativePath>|<relativePath>${new_relative_path}</relativePath>|g" "$pom_file"
            cat $pom_file
        fi
    done
    cp -r ${UNIQUE_WORKSPACE}/src/${INTERFACE_NAME}/$repo_name/src/* ${UNIQUE_WORKSPACE}/src/${INTERFACE_NAME}
    rm -rf ${repo_name}
    ls -l
done
