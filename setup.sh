#!/bin/bash

# Define the configuration file name
CONFIG_FILE="./config/default.toml"

setup_node() {
    echo "Checking Node.js installation..."
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null
    then
        echo "Node.js or npm is not installed. Installing Node.js LTS version..."
        # Add NodeSource APT repository for Node.js LTS version
        # This method is widely recommended for most Debian/Ubuntu-based systems
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
        echo "Node.js and npm installed successfully."
    else
        echo "Node.js and npm are already installed."
        node_version=$(node -v)
        npm_version=$(npm -v)
        echo "Node.js version: $node_version"
        echo "npm version: $npm_version"
    fi
}

# Function to set up Docker
setup_docker() {
    echo "Checking Docker installation..."
    if ! command -v docker &> /dev/null
    then
        echo "Docker is not installed. Installing Docker..."
        # Install Docker based on OS (example for Ubuntu/Debian)
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          \"$(. /etc/os-release && echo "$VERSION_CODENAME")\" stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        echo "Docker installed successfully."
        # Add current user to docker group to run docker commands without sudo
        sudo usermod -aG docker "$USER"
        echo "Please log out and log back in for Docker group changes to take effect, or run 'newgrp docker'."
    else
        echo "Docker is already installed."
    fi
}

# Function to set up Redis using Docker
setup_redis() {
    echo "Setting up Redis using Docker..."

    # Check if Redis container already exists and is running
    if docker ps -a --format '{{.Names}}' | grep -q "my-redis-container"; then
        echo "Redis container 'my-redis-container' already exists."
        if docker ps --format '{{.Names}}' | grep -q "my-redis-container"; then
            echo "Redis container is already running."
        else
            echo "Starting existing Redis container..."
            docker start my-redis-container
        fi
    else
        echo "Pulling Redis Docker image..."
        docker pull redis/redis-stack-server:latest # Using redis-stack-server for a more complete Redis experience with modules, or use redis:latest for basic Redis

        echo "Running Redis container 'my-redis-container' on port 6379..."
        # Run Redis container, mapping port 6379 from container to host
        # --name: assign a name to the container
        # -d: run in detached mode (in the background)
        # -p 6379:6379: map host port 6379 to container port 6379
        docker run --name my-redis-container -d -p 6379:6379 redis/redis-stack-server:latest
        # You can use 'redis:latest' if you only need basic Redis without the stack
        # docker run --name my-redis-container -d -p 6379:6379 redis:latest
    fi

    echo "Redis setup complete. You can connect to Redis on localhost:6379"
    echo "To check Redis container status: docker ps"
    echo "To stop Redis container: docker stop my-redis-container"
    echo "To remove Redis container: docker rm my-redis-container"
}

# Function to update configuration
update_config() {
    echo "Updating application configuration..."


    read -p "Enter Wild Duck Server Hostname(e.g., 0xmail.com): " wildduck_hostname
    read -p "Enter Wild Duck Access Token: " wildduck_access_token
    read -p "Enter your desired domain (will be used for email address e.g., 0xmail.com): " user_domain

    echo "Updating $CONFIG_FILE with provided details..."

    API_URL="https://$wildduck_hostname"
    # Update [api] section
    sed -i "s|url=\".*\"|url=\"$API_URL\"|" "$CONFIG_FILE" || echo "Failed to update url"
    sed -i "s|accessToken=\".*\"|accessToken=\"$wildduck_access_token\"|" "$CONFIG_FILE"

    # Update [service] section
    sed -i "s|domain=\".*\"|domain=\"$user_domain\"|" "$CONFIG_FILE"
    # Update the domains array - this assumes it's on a single line and only contains "localhost"
    sed -i "s|domains=\[.*\]|domains=[\"$user_domain\"]|" "$CONFIG_FILE"

    # Update [setup] section hostnames
    sed -i "s|hostname=\".*\"|hostname=\"$wildduck_hostname\"|" "$CONFIG_FILE"

    echo "Use default ports for imap, pop3 and smtp? [Y/n]"
    IMAP_PORT="993"
    POP3_PORT="995"
    SMTP_PORT="465"
    read -r yn
    case "$yn" in
      [Nn]* )
          echo "Please enter the port for IMAP (default: 993):"
          read -r input && IMAP_PORT="${input:-993}"

          echo "Please enter the port for POP3 (default: 995):"
          read -r input && POP3_PORT="${input:-995}"

          echo "Please enter the port for SMTP (default: 465):"
          read -r input && SMTP_PORT="${input:-465}"
          ;;
      * )
          echo "Using default ports for imap, pop3 and smtp"
          ;;
    esac
    sed -i "/\[setup.imap\]/,/^ *port *=/ s/^\( *port *= *\).*/\1$IMAP_PORT/"  "$CONFIG_FILE"
    sed -i "/\[setup.pop3\]/,/^ *port *=/ s/^\( *port *= *\).*/\1$POP3_PORT/"  "$CONFIG_FILE"
    sed -i "/\[setup.smtp\]/,/^ *port *=/ s/^\( *port *= *\).*/\1$SMTP_PORT/"  "$CONFIG_FILE"


    echo "Configuration update complete. Check $CONFIG_FILE for changes."
}


install_dependencies() {
  npm install
  npm run bowerdeps
}

# Main setup function
setup() {
    echo "Starting project setup..."
    setup_node
    setup_docker
    setup_redis
    update_config
    echo "Project setup finished."
    echo "running project"
    npm start
}

# Execute the main setup function
setup
