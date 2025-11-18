
import sys

# Specify the path to your pom.xml file
pom_file_path = sys.argv[1]

# Read the content of the pom.xml file
with open(pom_file_path, "r") as file:
    content = file.read()

# Check if the sanofi-artifactory string is present
if "sanofi-artifactory" in content:
    print("sanofi-artifactory string already exists in the pom.xml file. No modifications needed.")
else:
    # Create the repository block
    repository_block = """
    <repositories>
        <repository>
            <id>artifactory</id>
            <name>sanofi-artifactory</name>
            <url>https://sanofi.jfrog.io/artifactory/maven-chc-maven-local</url>
        </repository>
    </repositories>
    """

    # Find the position to insert the repository block
    insert_position = content.find("</project>")

    if insert_position != -1:
        # Insert the repository block before the closing </project> tag
        updated_content = content[:insert_position] + repository_block + content[insert_position:]

        # Write the modified pom.xml file
        with open(pom_file_path, "w") as file:
            file.write(updated_content)
    else:
        print("Error: Unable to find the </project> tag in the pom.xml file.")
