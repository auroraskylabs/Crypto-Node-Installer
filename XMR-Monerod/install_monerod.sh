#!/bin/bash

# Check if script is being run by root user
if [ "$(id -u)" -eq 0 ]; then
    echo -e "\e[31mWarning: Installing Monerod as the root user is not recommended for security reasons.\e[0m"
    read -p "Do you want to create a new user named 'monero' for this installation? (y/n): " create_monero_user
    if [ "$create_monero_user" == "y" ]; then
        # Create user 'monero'
        sudo useradd -m -s /bin/bash monero
        # Check if user 'monero' was created successfully
        if id "monero" &>/dev/null; then
            echo "User 'monero' created successfully."
        else
            echo "Failed to create user 'monero'. Exiting."
            exit 1
        fi
        # Switch to user 'monero'
        sudo -u monero bash -c "$(declare -f install_monerod_service); install_monerod_service"
        exit
    else
        echo "Installation aborted."
        exit 0
    fi
fi

# Function to check if a package is installed
check_dependency() {
    if dpkg -l "$1" &> /dev/null; then
        echo -e "\e[32m$1 is installed.\e[0m"
    else
        echo -e "\e[31m$1 is not found.\e[0m"
        missing_dependencies+=("$1")
    fi
}

# Function to display progress bar
progress_bar() {
    local duration=$1
    local columns=$(tput cols)
    local progress_char="▉"
    local progress_length=$((columns / 2))
    local sleep_time=$((duration / progress_length))
    for ((i = 0; i < progress_length; i++)); do
        echo -ne "\e[32m$progress_char\e[0m"
        sleep $sleep_time
    done
    echo
}

# Function to install Monerod service
install_monerod_service() {
    # Check dependencies
    echo "Checking dependencies..."
    declare -a missing_dependencies=()
    check_dependency "git"
    check_dependency "build-essential"
    check_dependency "cmake"
    check_dependency "libboost-all-dev"
    check_dependency "miniupnpc"
    check_dependency "libunbound-dev"
    check_dependency "graphviz"
    check_dependency "doxygen"
    check_dependency "libunwind-dev"
    check_dependency "pkg-config"
    check_dependency "libssl-dev"
    check_dependency "liblzma-dev"
    check_dependency "libreadline-dev"
    check_dependency "libldns-dev"
    check_dependency "libexpat1-dev"
    check_dependency "libgtest-dev"
    check_dependency "libzmq3-dev"

    # Prompt user to install missing dependencies
    if [ ${#missing_dependencies[@]} -eq 0 ]; then
        echo "All dependencies are installed."
    else
        echo "The following dependencies are missing:"
        for dependency in "${missing_dependencies[@]}"; do
            echo -e "\e[31m$dependency\e[0m"
        done
        read -p "Do you want to install the missing dependencies? (y/n): " choice
        if [ "$choice" == "y" ]; then
            echo "Installing missing dependencies..."
            progress_bar 10
            sudo apt install "${missing_dependencies[@]}"
        else
            echo "Installation aborted."
            exit 0
        fi
    fi

    # Clone Monero repository
    git clone --recursive https://github.com/monero-project/monero.git
    cd monero

    # Build Monerod
    echo "Building Monerod..."
    make -j$(nproc) | progress_bar 20

    # Install Monerod
    echo "Installing Monerod..."
    sudo make install | progress_bar 10

    # Ask if user wants to install Monerod as a service
    read -p "Do you want to install Monerod as a system service? (y/n): " install_service
    if [ "$install_service" == "y" ]; then
        echo "A system service allows Monerod to run in the background and start automatically on boot."
        read -p "Do you want to install Monerod as a system service? (y/n): " install_service_confirm
        if [ "$install_service_confirm" == "y" ]; then
            # Create systemd service unit file
            sudo bash -c 'cat > /etc/systemd/system/monerod.service' << EOF
[Unit]
Description=Monero Node
After=network.target

[Service]
User=$(whoami)
Group=$(id -gn)
ExecStart=/usr/local/bin/monerod --detach --data-dir=$HOME/.bitmonero
Restart=always
RestartSec=10
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

            # Reload systemd
            echo "Reloading systemd..."
            sudo systemctl daemon-reload | progress_bar 5

            # Enable Monerod service
            echo "Enabling Monerod service..."
            sudo systemctl enable monerod | progress_bar 5

            # Start Monerod service
            echo "Starting Monerod service..."
            sudo systemctl start monerod | progress_bar 5

            # Check if Monerod service is running
            if sudo systemctl is-active --quiet monerod; then
                echo "Monerod service is running."
            else
                echo "Monerod service is not running. Please check the installation."
            fi
        else
            echo "Monerod will not be installed as a system service."
        fi
    else
        echo "Monerod will not be installed as a system service."
    fi

    echo "Monerod installation completed successfully!"
}

# Call the function to install Monerod service
install_monerod_service
