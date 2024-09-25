#!/bin/bash

# Help message function
function show_help() {
  echo "Usage: $0 --a <axess_container_name> --db <db_container_name> --n <network_name> --aip <artifacts_ip>"
  echo ""
  echo "  --a    Name for the AXESS container"
  echo "  --db   Name for the MySQL database container"
  echo "  --n    Name for the Docker network"
  echo "  --aip  IP address for the artifacts host"
  echo ""
  echo "All parameters are required."
  exit 1
}

# Colorful output
function echo_color() {
  echo -e "\033[1;32m$1\033[0m"
}

# Check if enough arguments are provided
if [[ $# -lt 8 ]]; then
  show_help
fi

# Parse input arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --a) axess_container_name="$2"; shift ;;
    --db) db_container_name="$2"; shift ;;
    --n) network_name="$2"; shift ;;
    --aip) artifacts_ip="$2"; shift ;;
    *) echo "Unknown parameter: $1"; show_help ;;
  esac
  shift
done

# Check if all parameters are set
if [[ -z "$axess_container_name" || -z "$db_container_name" || -z "$network_name" || -z "$artifacts_ip" ]]; then
  show_help
fi

# Function to safely add/update an entry in known_hosts
function add_or_update_known_host() {
    local host=$1
    local known_hosts_file=~/.ssh/known_hosts
    
    # Check if the host exists in known_hosts and remove if found
    if grep -q "$host" $known_hosts_file; then
        echo_color "Updating known_hosts for $host"
        # Remove the existing entry
        grep -v "$host" $known_hosts_file > ${known_hosts_file}.tmp
        mv ${known_hosts_file}.tmp $known_hosts_file
    else
        echo_color "Adding $host to known_hosts"
    fi
    
    # Add the new entry from ssh-keyscan
    ssh-keyscan $host >> $known_hosts_file
}

# Ensure the .ssh directory exists
mkdir -p ~/.ssh

# Add or update the hosts
add_or_update_known_host "gitlab.axiros.com"
add_or_update_known_host "git.axiros.com"

# Step 1: Create Dockerfile for AXESS container
echo_color "Creating Dockerfile for AXESS container..."
cat <<EOF > Dockerfile
FROM debian:bookworm as $axess_container_name
RUN apt-get update && apt-get -y install ssh git git-lfs vim
CMD ["sleep", "infinity"]
EOF

# Step 2: Build the Docker image
echo_color "Building the Docker image..."
docker build -f Dockerfile -t $axess_container_name .

# Step 3: Run the AXESS container with the specified host IP
echo_color "Running the AXESS container..."
docker run -d --add-host artifacts-internal.axiros.com:$artifacts_ip --name $axess_container_name $axess_container_name

# Step 4: Copy SSH key to AXESS container
echo_color "Copying SSH keys to AXESS container..."
docker cp ~/.ssh/id_rsa $axess_container_name:/root/.ssh/id_rsa
docker cp ~/.ssh/known_hosts $axess_container_name:/root/.ssh/known_hosts

# Step 5: Create the Docker network
echo_color "Creating the Docker network..."
docker network create $network_name

# Step 6: Run the MySQL database container
echo_color "Running the MySQL database container..."
docker run --name $db_container_name \
           --hostname mysql \
           --network $network_name \
           -e MYSQL_ROOT_PASSWORD=root \
           -d mysql:8.0 \
           --sql_mode='' \
           --transaction-isolation=READ-COMMITTED

# Step 7: Connect AXESS container to the Docker network
echo_color "Connecting AXESS container to the Docker network..."
docker network connect $network_name $axess_container_name

# Step 8: Inside AXESS container, clone the repository and initialize
echo_color "Cloning AXESS repository and initializing..."
docker exec $axess_container_name bash -c "git clone git@gitlab.axiros.com:axess/axess.git /opt/axess"
docker exec $axess_container_name bash -c "cd /opt/axess && git-lfs pull"
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh init_dev"
# Step 9: Installing external dependencies
echo_color "Installing Axess external dependencies..."
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh install_external"
# Step 10: Building gui
echo_color "Building Axess GUI..."
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh build_gui_dev"
# Step 11: Building SP
echo_color "Building Axess SP..."
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh build_sp_dev"
# Step 12: Deploying Axess
echo_color "Deploying Axess..."
docker exec $axess_container_name bash -c "/opt/axess/bin/deploy"
# Step 13: Creating admin user
echo_color "Creating admin user..."
docker exec $axess_container_name bash -c "/opt/axess/bin/python /opt/axess/dev/create_adminax_user.py"
# Step 14: Generating API docs
echo_color "Generating API docs..."
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh generate_api_doc"
# Step 15: enerating config docs
echo_color "Generating config docs..."
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh generate_config_doc"

# Step 16: Set Git safe directories inside AXESS container
echo_color "Setting Git safe directories..."
safe_dirs=(
  "/opt/configcontroller/ext/axlib"
  "/opt/configcontroller/ext/yang_definitions"
  "/opt/configcontroller/ext/axess"
  "/opt/configcontroller/ext/udi"
  "/opt/configcontroller"
  "/opt/tr069controller/ext/axlib"
  "/opt/tr069controller/ext/yang_definitions"
  "/opt/tr069controller/ext/axess"
  "/opt/tr069controller/ext/udi"
  "/opt/tr069controller"
)

for dir in "${safe_dirs[@]}"; do
  docker exec $axess_container_name git config --global --add safe.directory "$dir"
done

# Step 17: Clone and initialize the TR069 controller
echo_color "Cloning and initializing the TR069 controller..."
docker exec $axess_container_name bash -c "git clone git@gitlab.axiros.com:axess/tr069controller.git /opt/tr069controller"
docker exec $axess_container_name bash -c "cd /opt/tr069controller && ./common.sh init_dev"

# Step 18: Clone and initialize the Config Controller
echo_color "Cloning and initializing the Config Controller..."
docker exec $axess_container_name bash -c "git clone git@gitlab.axiros.com:axess/configcontroller.git /opt/configcontroller"
docker exec $axess_container_name bash -c "cd /opt/configcontroller && ./common.sh init_dev"

# QoL Improvements
# 1a. Change SERVICE_ENABLED in ax.graphite-web
echo_color "Updating /etc/default/ax.graphite-web..."
docker exec $axess_container_name bash -c 'sed -i "s/^SERVICE_ENABLED=\"false\"/SERVICE_ENABLED=\"true\"/" /etc/default/ax.graphite-web'

# 1b. Configure grafana dashboards
echo_color "Configuring grafana dashboards"
docker exec $axess_container_name bash -c "/etc/init.d/openresty start"
docker exec $axess_container_name bash -c "/etc/init.d/grafana-server start"
sleep 1m
docker exec $axess_container_name bash -c "/opt/axess/bin/configure_grafana"
docker exec $axess_container_name bash -c "/etc/init.d/grafana-server stop"
docker exec $axess_container_name bash -c "/etc/init.d/openresty stop"

# 2. Checkout tools repository
echo_color "Checking out the tools repository..."
docker exec $axess_container_name bash -c "git clone https://github.com/pjuwyD/tools.git /opt/tools"

# 3. Create helper_scripts directory and copy files
echo_color "Creating helper_scripts directory and copying files..."
docker exec $axess_container_name bash -c "mkdir /opt/helper_scripts && cp /opt/tools/axess_help/helper_scripts/* /opt/helper_scripts"

# 4. Give all grants to helper scripts
echo_color "Setting permissions for helper scripts..."
docker exec $axess_container_name bash -c "chmod +x /opt/helper_scripts/*"

# 5. Install zsh and oh-my-zsh
echo_color "Installing zsh and Oh My Zsh..."
docker exec -it $axess_container_name bash -c "apt-get install --assume-yes zsh && yes | sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""

# 6. Copy zshrc and set up plugins/themes
echo_color "Setting up zsh configuration and plugins..."
docker exec $axess_container_name bash -c "cp /opt/tools/axess_help/zshrc_update1 ~/.zshrc"
docker exec $axess_container_name bash -c "git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
docker exec $axess_container_name bash -c "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
docker exec $axess_container_name bash -c "cp /opt/tools/axess_help/p10k.zsh ~/.p10k.zsh"

# Cleanup
echo_color "Cleanup..."
rm Dockerfile
docker exec $axess_container_name bash -c "rm -rf /opt/tools"

# Summary of steps performed
echo_color "AXESS setup complete! Here’s a summary of the steps performed:"
echo ""
echo -e "\033[1;34mStep\033[0m | \033[1;34mDescription\033[0m"
echo "-----------------------------------------------------------"
echo -e "1. \033[1;32mDockerfile Creation\033[0m | Created a Dockerfile for the AXESS container."
echo -e "2. \033[1;32mDocker Image Build\033[0m | Built the AXESS Docker image."
echo -e "3. \033[1;32mContainer Run\033[0m | Ran the AXESS container with specified host IP."
echo -e "4. \033[1;32mSSH Keys Copy\033[0m | Copied SSH keys to AXESS container."
echo -e "5. \033[1;32mDocker Network Creation\033[0m | Created the Docker network."
echo -e "6. \033[1;32mMySQL Container Run\033[0m | Ran the MySQL database container."
echo -e "7. \033[1;32mNetwork Connection\033[0m | Connected AXESS container to the Docker network."
echo -e "8. \033[1;32mRepo Cloning\033[0m | Cloned AXESS repository and initialized."
echo -e "9. \033[1;32mInstaling external dependencies\033[0m | Clickhouse, Elasticsearch, Filebeat..."
echo -e "10. \033[1;32mBuild GUI\033[0m | Build Axess GUI."
echo -e "11. \033[1;32mBuild SP\033[0m | Build Axess support portal."
echo -e "12. \033[1;32mDeploy Axess\033[0m | Deploy Axess application."
echo -e "13. \033[1;32mCreate admin user\033[0m | Admin user (admin:ax) created."
echo -e "14. \033[1;32mGenerate API docs\033[0m | Generate API swagger documentation."
echo -e "15. \033[1;32mGenerate config docs\033[0m | Generate config documentation."
echo -e "16. \033[1;32mGit Safe Directories\033[0m | Set safe directories for Git."
echo -e "17. \033[1;32mTR069 Controller\033[0m | Cloned and initialized the TR069 controller."
echo -e "18. \033[1;32mConfig Controller\033[0m | Cloned and initialized the Config Controller."
echo -e "19. \033[1;32mQoL Improvements\033[0m | Updated configurations, copied helper scripts, installed zsh, and set up plugins."

# Display aliases
echo ""
echo_color "Included Aliases:"
echo -e "\033[1;34mAlias\033[0m | \033[1;34mDescription\033[0m"
echo "----------------------------------------------------------"
echo -e "debug_axess \033[0m| \033[1;32mStarts Axess process in the foreground with all important background processes.\033[0m"
echo -e "debug_northbound \033[0m| \033[1;32mStarts Axess Northbound in the foreground.\033[0m"
echo -e "debug_tr \033[0m| \033[1;32mStarts tr069controller process in the foreground.\033[0m"
echo -e "debug_conf \033[0m| \033[1;32mStarts configcontroller process in the foreground.\033[0m"
echo -e "ax_start \033[0m| \033[1;32mStarts all axess processes in the background (including graphite and grafana).\033[0m"
echo -e "ax_stop \033[0m| \033[1;32mStops all axess processes.\033[0m"
echo -e "ax_status \033[0m| \033[1;32mDisplays the running status of all axess processes.\033[0m"

echo_color "Setup completed successfully!"