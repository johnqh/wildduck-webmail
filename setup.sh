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

setup_docker() {
    echo "Checking Docker installation..."
    if command -v docker &> /dev/null
    then
        echo "Docker is already installed."
    else
        echo "Docker is not installed. Attempting to install..."
        OS=$(uname -s)

        case "$OS" in
            # macOS
            Darwin)
                echo "Detected macOS. Installing Docker via Homebrew..."
                # Check for Homebrew, install if not present
                if ! command -v brew &> /dev/null
                then
                    echo "Homebrew not found. Installing Homebrew..."
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                fi
                
                # Install Docker Desktop with Homebrew
                brew install --cask docker
                echo "Docker Desktop for macOS has been installed."
                echo "Please open the Docker Desktop application from your Applications folder to complete the setup."
                echo "After installation, restart your computer and ensure Docker Desktop is running."
                exit
                ;;

            # Linux
            Linux)
                echo "Detected Linux. Installing Docker using the official convenience script..."
                # The official convenience script from Docker works on a wide range of Linux distributions.
                # It's not recommended for production, but is perfect for development environments.
                curl -fsSL https://get.docker.com -o get-docker.sh
                sudo sh get-docker.sh
                rm get-docker.sh
                
                # Add current user to docker group
                sudo usermod -aG docker "$USER"
                echo "Docker installed successfully."
                echo "Please log out and log back in for Docker group changes to take effect, or run 'newgrp docker'."
                exit
                ;;

            # Windows (handled with a message, as command-line installation is not the primary method)
            *)
                echo "Unsupported OS or Windows detected."
                echo "For Windows, the recommended method is to install Docker Desktop from the official website."
                echo "Please download the installer from https://www.docker.com/products/docker-desktop/"
                echo "After installation, restart your computer and ensure Docker Desktop is running."
                exit 
                ;;
        esac
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

    # Determine the correct sed in-place edit flag
    SED_INPLACE_FLAG=""
    if [[ "$(uname -s)" == "Darwin" ]]; then
        SED_INPLACE_FLAG="-i ''"
    else
        SED_INPLACE_FLAG="-i"
    fi

    # Check for CONFIG_FILE existence
    if [ -z "$CONFIG_FILE" ]; then
        echo "Error: CONFIG_FILE variable is not set."
        return 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file '$CONFIG_FILE' not found."
        return 1
    fi

    read -p "Enter Wild Duck Server Hostname(e.g., 0xmail.com): " wildduck_hostname
    read -p "Enter Wild Duck Access Token: " wildduck_access_token
    read -p "Enter your desired domain (will be used for email address e.g., 0xmail.com): " user_domain

    echo "Updating $CONFIG_FILE with provided details..."

    API_URL="https://$wildduck_hostname"

    # Update [api] section
    eval sed $SED_INPLACE_FLAG "s|url=\".*\"|url=\"$API_URL\"|" "$CONFIG_FILE" || echo "Failed to update url"
    eval sed $SED_INPLACE_FLAG "s|accessToken=\".*\"|accessToken=\"$wildduck_access_token\"|" "$CONFIG_FILE"

    # Update [service] section
    eval sed $SED_INPLACE_FLAG "s|domain=\".*\"|domain=\"$user_domain\"|" "$CONFIG_FILE"
    # Update the domains array - this assumes it's on a single line
    eval sed $SED_INPLACE_FLAG "s|domains=\[.*\]|domains=[\"$user_domain\"]|" "$CONFIG_FILE"

    # Update [setup] section hostnames
    eval sed $SED_INPLACE_FLAG "s|hostname=\".*\"|hostname=\"$wildduck_hostname\"|" "$CONFIG_FILE"

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

    # Update ports
    eval sed $SED_INPLACE_FLAG "/\[setup.imap\]/,/^ *port *=/ s/^\( *port *= *\).*/\1$IMAP_PORT/" "$CONFIG_FILE"
    eval sed $SED_INPLACE_FLAG "/\[setup.pop3\]/,/^ *port *=/ s/^\( *port *= *\).*/\1$POP3_PORT/" "$CONFIG_FILE"
    eval sed $SED_INPLACE_FLAG "/\[setup.smtp\]/,/^ *port *=/ s/^\( *port *= *\).*/\1$SMTP_PORT/" "$CONFIG_FILE"

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
