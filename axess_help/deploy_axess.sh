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
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh install_external"
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh build_gui_dev"
docker exec $axess_container_name bash -c "cd /opt/axess && ./common.sh build_sp_dev"
docker exec $axess_container_name bash -c "/opt/axess/bin/deploy"
docker exec $axess_container_name bash -c "/opt/axess/bin/python /opt/axess/dev/create_adminax_user.py"

# Step 9: Set Git safe directories inside AXESS container
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

# Step 10: Clone and initialize the TR069 controller
echo_color "Cloning and initializing the TR069 controller..."
docker exec $axess_container_name bash -c "git clone git@gitlab.axiros.com:axess/tr069controller.git /opt/tr069controller"
docker exec $axess_container_name bash -c "cd /opt/tr069controller && ./common.sh init_dev"

# Step 11: Clone and initialize the Config Controller
echo_color "Cloning and initializing the Config Controller..."
docker exec $axess_container_name bash -c "git clone git@gitlab.axiros.com:axess/configcontroller.git /opt/configcontroller"
docker exec $axess_container_name bash -c "cd /opt/configcontroller && ./common.sh init_dev"

# QoL Improvements
# 1. Change SERVICE_ENABLED in ax.graphite-web
echo_color "Updating /etc/default/ax.graphite-web..."
docker exec $axess_container_name bash -c 'sed -i "s/^SERVICE_ENABLED=\"false\"/SERVICE_ENABLED=\"true\"/" /etc/default/ax.graphite-web'

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
docker exec -it $axess_container_name bash -c "apt-get install --assume-yes zsh && sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""

# 6. Copy zshrc and set up plugins/themes
echo_color "Setting up zsh configuration and plugins..."
docker exec $axess_container_name bash -c "cp /opt/tools/axess_help/zshrc_update1 ~/.zshrc"
docker exec $axess_container_name bash -c "git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
docker exec $axess_container_name bash -c "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
docker exec $axess_container_name bash -c "cp /opt/tools/axess_help/p10k.zsh ~/.p10k.zsh"

echo_color "AXESS setup complete!"

