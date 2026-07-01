#!/bin/bash
# set -x

# Function to wait for Zato server with curl instead of zato wait
wait_for_zato_server() {
    log_verbose "Waiting for Zato server to become available (timeout: 60s)"

    # Initialize variables
    local timeout=60          # Total timeout in seconds
    local interval=1          # Interval between attempts in seconds
    local start_message_timeout=6 # Show "Starting server" message after this many seconds
    local message_shown=false # Flag to track if message has been shown
    local attempts=0          # Counter for attempts
    local max_attempts=$((timeout / interval))  # Calculate max attempts based on timeout and interval

    # Run until we get a proper response or reach timeout
    while [ $attempts -lt $max_attempts ]; do
        # Check if we should show the "Starting server" message (but only once)
        if [ $attempts -gt $start_message_timeout ] && [ "$message_shown" = false ]; then
            # Force the message to display regardless of verbose setting
            echo -e "\e[36m[$(date "+%Y-%m-%d %H:%M:%S")]\e[0m \e[33mStarting server\e[0m"
            message_shown=true
        fi

        # Try to ping the server
        local response=$(curl -s "http://localhost:${Zato_Port_Server}/zato/ping" 2>/dev/null)

        # Check if we got a response containing "pong"
        if [[ "$response" == *"pong"* ]]; then
            log_verbose "Server is available after $attempts attempts (${attempts}s)"
            return 0
        fi

        # Wait for the specified interval before next attempt
        sleep $interval
        attempts=$((attempts + 1))
    done

    # If we reached the timeout
    echo -e "\e[36m[$(date "+%Y-%m-%d %H:%M:%S")]\e[0m \e[31mServer not available after ${timeout} seconds\e[0m"
    return 1
}

# Function to create a JSON file with Zato environment details
create_zato_env_details_json() {
    local dashboard_password=$(cat /opt/zato/env/details/zato-dashboard-admin-password.txt)
    local ide_password=$(cat /opt/zato/env/details/zato-ide-publisher-password.txt)
    local ssh_password=$(cat /opt/zato/env/details/zato-ssh-user-password.txt)

    # Create the JSON file
    cat > /opt/zato/env/details/all-zato-env-details.json << EOF
{
    "zato_dashboard_admin_username": "admin",
    "zato_dashboard_admin_password": "${dashboard_password}",
    "zato_ide_publisher_username": "ide_publisher",
    "zato_ide_publisher_password": "${ide_password}",
    "zato_ssh_username": "zato",
    "zato_ssh_password": "${ssh_password}",
    "zato_env_path": "${Zato_Env_Path}"
}
EOF

    # Set proper permissions
    chown zato:zato /opt/zato/env/details/all-zato-env-details.json
    chmod 644 /opt/zato/env/details/all-zato-env-details.json

    # Log the action
    log_verbose "Created Zato environment details JSON at /opt/zato/env/details/all-zato-env-details.json"

    # Create ASCII table text file
    create_zato_env_details_txt "${dashboard_password}" "${ide_password}" "${ssh_password}"
}

# Function to create a pretty ASCII table with Zato environment details
create_zato_env_details_txt() {
    local dashboard_password="$1"
    local ide_password="$2"
    local ssh_password="$3"

    # Determine the max length for nice formatting
    local max_value_length=0

    # Check each value's length to determine table width
    local values=("admin" "${dashboard_password}" "ide_publisher" "${ide_password}" "zato" "${ssh_password}" "${Zato_Env_Path}")
    for val in "${values[@]}"; do
        if [ ${#val} -gt $max_value_length ]; then
            max_value_length=${#val}
        fi
    done

    # Add some padding
    max_value_length=$((max_value_length + 2))

    # Calculate total width of table
    local label_width=19
    local total_width=$((label_width + max_value_length + 7))  # +7 for borders and spacing

    # Create horizontal separator line
    local separator=$(printf '%*s' "$total_width" | tr ' ' '-')

    # Function to add padding to a value to align the table
    add_padding() {
        local value="$1"
        local target_length=$max_value_length
        local padding_needed=$((target_length - ${#value}))
        printf "%-${target_length}s" "$value"
    }

    # Function to format header row consistently
    format_header() {
        local header="$1"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "$header" "Value"
    }

    # Create the ASCII table
    {
        echo "$separator"
        format_header "Category"
        echo "$separator"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "Dashboard user" "admin"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "Dashboard password" "$dashboard_password"
        echo "$separator"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "SSH user" "zato"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "SSH password" "$ssh_password"
        echo "$separator"
        format_header "Port Information"
        echo "$separator"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "Dashboard port" "$Zato_Port_Dashboard"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "Dashboard port SSL" "8184"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "Server port" "$Zato_Port_Load_Balancer"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "Server port SSL" "$Zato_Port_Load_Balancer_SSL"
        printf "| %-${label_width}s | %-${max_value_length}s |\n" "SSH port" "$Zato_Port_SSH"
        echo "$separator"
    } > /opt/zato/env/details/all-zato-env-details.txt

    # Set proper permissions
    chown zato:zato /opt/zato/env/details/all-zato-env-details.txt
    chmod 644 /opt/zato/env/details/all-zato-env-details.txt

    # Log the action
    log_verbose "Created Zato environment details ASCII table at /opt/zato/env/details/all-zato-env-details.txt"

    # Update log_env_details function to display the text file as well
    log_verbose "ASCII table created at: /opt/zato/env/details/all-zato-env-details.txt"
}

# Function to log environment details if requested
log_env_details() {
    if [ "$Zato_Log_Env_Details" = "True" ] || [ "$Zato_Log_Env_Details" = "true" ]; then
        create_zato_env_details_json
    fi
}

# Function to run custom scripts
run_custom_scripts() {
    local phase="$1"
    if [ -d "/opt/hot-deploy/scripts" ]; then
        log_verbose "Running custom scripts $phase"
        for script in $(ls /opt/hot-deploy/scripts/*.sh 2>/dev/null | sort); do
            if [ -f "$script" ]; then
                log_verbose "Running script: $script"
                su - zato -c "bash $script $phase"
            fi
        done
    fi
}

# ##############################################################################################

# Trap SIGINT (Ctrl-C) and SIGTERM to exit gracefully with status code 0
trap 'echo -e "\e[36m[$(date "+%Y-%m-%d %H:%M:%S")]\e[0m \e[33mReceived shutdown signal. Exiting.\e[0m"; exit 0' SIGINT SIGTERM

# Function to generate random password
generate_password() {
    local prefix=$1
    echo "${prefix}.$(head /dev/urandom | tr -dc a-z0-9 | head -c 20)"
}

# Function to get timestamp with current timezone
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S %Z"
}

# Enhanced logging function with timestamp and colors - always output important messages
log_timestamp() {
    local timestamp=$(get_timestamp)
    # Always output regardless of Zato_Suppress_Output setting
    echo -e "\e[36m[$timestamp]\e[0m $1"  # Cyan color for timestamp
}

# Function to echo verbose logs with timestamp - only if verbose flag is set
log_verbose() {
    if $is_verbose; then
        local timestamp=$(get_timestamp)
        echo -e "\e[33m[$timestamp] [VERBOSE]\e[0m $1"  # Yellow color for verbose logs
    fi
}

# Set verbose flag if either Zato_Build_Verbosity or Zato_Verbose are set
is_verbose=false
if [ -n "$Zato_Build_Verbosity" ] || [ -n "$Zato_Verbose" ]; then
    is_verbose=true
fi

# Set up file descriptors for output control based on Zato_Build_Verbose
if [ "$Zato_Build_Verbose" = "true" ] || [ "$Zato_Build_Verbose" = "True" ] || [ "$Zato_Build_Verbose" = "1" ]; then
    exec 3>&1 4>&2
else
    exec 3>/dev/null 4>/dev/null
fi

# Set verbosity flag for commands
if $is_verbose; then
    VERBOSE_FLAG="--verbose"
    # Only enable command echo if we're NOT suppressing output
    if [ "$Zato_Suppress_Output" != "True" ]; then
        set -x  # Enable command echo
    fi
else
    VERBOSE_FLAG=""
fi

# Function to dynamically add Zato environment variables to a file
add_zato_vars_to_file() {
    local file=$1
    local tmp_file="${file}.tmp"

    # Use the existing log_verbose function if it exists in the script
    if type log_verbose &>/dev/null; then
        log_verbose "Adding Zato environment variables to $file"
    fi

    # First, remove any existing Zato_ exports from the file
    sed -i '/^export Zato_/d' "$file"
    sed -i '/^export ZATO_/d' "$file"
    # Also remove any existing proxy exports from the file
    sed -i '/^export HTTP_PROXY/d' "$file"
    sed -i '/^export HTTPS_PROXY/d' "$file"
    sed -i '/^export http_proxy/d' "$file"
    sed -i '/^export https_proxy/d' "$file"
    sed -i '/^export NO_PROXY/d' "$file"
    sed -i '/^export no_proxy/d' "$file"
    sed -i '/^export SSL_CERT_FILE/d' "$file"
    sed -i '/^export REQUESTS_CA_BUNDLE/d' "$file"
    sed -i '/^# Dynamically added Zato/d' "$file"

    # Build the environment exports block
    local env_block=""
    env_block+="# Dynamically added Zato environment variables $(date)\n"

    # Add all environment variables starting with Zato (case-insensitive)
    for var in $(printenv | grep -i "^zato_" | sort); do
        var_name=$(echo "$var" | cut -d= -f1)
        var_value=$(echo "$var" | cut -d= -f2-)
        env_block+="export $var_name=\"$var_value\"\n"
    done

    # Add HTTP proxy environment variables if they are not empty
    for var_name in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy NO_PROXY no_proxy; do
        var_value=$(printenv "$var_name")
        if [ ! -z "$var_value" ]; then
            if type log_verbose &>/dev/null; then
                log_verbose "Adding proxy variable $var_name=$var_value to $file"
            fi
            env_block+="export $var_name=\"$var_value\"\n"
        fi
    done

    # Add SSL certificate environment variables
    env_block+="export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt\n"
    env_block+="export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt\n"

    # Insert the env block BEFORE the if statement that runs zato start
    awk -v env_block="$env_block" '/if \[\[.*COMPONENT_PATH/ || /if \[\[.*\/opt\/zato/ { printf "%s", env_block } { print }' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
    chmod +x "$file"
}
# Function to create startup scripts
create_startup_script() {
    local script_name="$1"
    local script_content="$2"
    local script_path="/opt/zato/env/qs-1/${script_name}"

    log_verbose "Creating startup script: ${script_name}"
    cat > "${script_path}" << EOF
#!/bin/bash
${script_content}
EOF
    chown zato:zato "${script_path}"
    chmod +x "${script_path}"
}

# Function to perform post-server-start operations
perform_post_server_operations() {

    # Run enmasse config import if files exist
    if [ -f "/opt/hot-deploy/enmasse/enmasse.yaml" ]; then
        log_timestamp "Importing enmasse configuration from /opt/hot-deploy/enmasse/enmasse.yaml"
        su - zato -c "export PYTHONWARNINGS=ignore && /opt/zato/current/bin/zato enmasse ${Zato_Env_Path}/server1 --import \
            --input /opt/hot-deploy/enmasse/enmasse.yaml --env-file /opt/hot-deploy/enmasse/env.ini \
            --exit-on-missing-file $VERBOSE_FLAG" >&3 2>&4
    fi

    if [ -f "/tmp/enmasse.yaml" ]; then
        log_timestamp "Importing enmasse configuration from /tmp/enmasse.yaml"
        su - zato -c "export PYTHONWARNINGS=ignore && /opt/zato/current/bin/zato enmasse ${Zato_Env_Path}/server1 --import \
            --input /tmp/enmasse.yaml --env-file /tmp/env.ini \
            --exit-on-missing-file $VERBOSE_FLAG" >&3 2>&4
    fi

    # Set IDE password without showing the password in the output
    log_verbose "Setting IDE password"
    su - zato -c "export PYTHONWARNINGS=ignore && /opt/zato/current/bin/zato set-ide-password ${Zato_Env_Path}/server1 --password \"$ZATO_IDE_PASSWORD\" $VERBOSE_FLAG" >&3 2>&4
}

# Suppress Python warnings globally by setting environment variable
export PYTHONWARNINGS="ignore"

# Generate unique passwords at runtime, respect environment variables if provided
log_verbose "Generating passwords"

# Use environment variables if provided, otherwise generate random passwords
ZATO_SSH_PASSWORD=${Zato_SSH_Password:-$(generate_password "zato.ssh")}
ZATO_IDE_PASSWORD=${Zato_IDE_Password:-$(generate_password "zato.ide")}
ZATO_DASHBOARD_PASSWORD=${Zato_Dashboard_Password:-$(generate_password "zato.dash")}
export Zato_Metrics_Password=${Zato_Metrics_Password:-$(generate_password "zato.server.metrics")}
export Zato_Load_Balancer_Stats_Password=${Zato_Load_Balancer_Stats_Password:-$(generate_password "zato.lb.stats")}
export Zato_Load_Balancer_Metrics_Password=${Zato_Load_Balancer_Metrics_Password:-$(generate_password "zato.lb.metrics")}

# If Zato_Password is set, use it for all passwords
if [ ! -z "$Zato_Password" ]; then
    log_verbose "Using global Zato_Password for all credentials"
    ZATO_SSH_PASSWORD=$Zato_Password
    ZATO_IDE_PASSWORD=$Zato_Password
    ZATO_DASHBOARD_PASSWORD=$Zato_Password
    export Zato_Load_Balancer_Stats_Password=$Zato_Password
    export Zato_Load_Balancer_Metrics_Password=$Zato_Password
fi

# Update CA certificates if requested
if [ "$Zato_Update_CA_Certificates" = "True" ] || [ "$Zato_Update_CA_Certificates" = "true" ]; then
    log_timestamp "Updating CA certificates"
    update-ca-certificates > /dev/null
fi

# Update Zato source code
log_verbose "Updating Zato source code"

#CHANGED
# su - zato -c "cd ~/current && git pull" >&3 2>&4 || true

# Install Zato requirements
log_verbose "Installing Zato requirements"

#CHANGED
# su - zato -c "export PYTHONWARNINGS=ignore && /opt/zato/current/bin/pip install --disable-pip-version-check -r ~/current/requirements.txt" >&3 2>&4 || true

if [ -n "$Zato_Env_Name" ]; then
    echo -e "\e[36m[$(get_timestamp)]\e[0m \e[32mStarting Zato: \e[31m${Zato_Env_Name}\e[0m"
else
    log_timestamp "Starting Zato"
fi

# Update Zato port configuration based on port configuration
update_zato_port_config() {
    local file=$1
    local default_port=$2
    local new_port=$3
    local port_desc=$4

    if [ -f "$file" ] && [ "$default_port" != "$new_port" ]; then
        log_verbose "Updating $port_desc port from $default_port to $new_port in $file"
        sed -i "s/:$default_port/:$new_port/g" "$file"
        sed -i "s/=$default_port/=$new_port/g" "$file"
    fi
}

# Set Python version for Zato
export ZATO_PYTHON_VERSION=${Zato_Python_Version}

# Make sure the directory exists
mkdir -p /opt/zato/env/details
chmod 755 /opt/zato/env/details

# Store passwords in files
log_verbose "Storing credential information in files"
echo "$ZATO_SSH_PASSWORD" > /opt/zato/env/details/zato-ssh-user-password.txt
echo "$ZATO_IDE_PASSWORD" > /opt/zato/env/details/zato-ide-publisher-password.txt

echo "$ZATO_DASHBOARD_PASSWORD" > /opt/zato/env/details/zato-dashboard-admin-password.txt
chown -R zato:zato /opt/zato/env/details/
chmod 644 /opt/zato/env/details/*.txt

create_zato_env_details_json

# Add zato user to ubuntu group
log_verbose "Adding zato user to ubuntu group"
usermod -a -G ubuntu zato 2>/dev/null

# Set SSH password for zato user - without showing output
log_verbose "Setting SSH password for zato user"
echo "zato:$ZATO_SSH_PASSWORD" | chpasswd 2>&4

sysctl -w kernel.yama.ptrace_scope=0 >&3 2>&4 || true

# Start Redis
log_verbose "Starting Redis"
redis-server /etc/redis/redis.conf --daemonize yes

# Start cron silently
log_verbose "Starting cron service"
service cron start >&3 2>&4 || log_timestamp "Failed to start cron"

# Update SSH port if needed - Fixed approach to avoid "Badly formatted port number" error
if [ "${Zato_Port_SSH}" != "22" ]; then
    log_verbose "Updating SSH port to ${Zato_Port_SSH}"
    # First remove any existing Port configuration lines
    sed -i '/^#Port/d' /etc/ssh/sshd_config
    sed -i '/^Port/d' /etc/ssh/sshd_config
    # Add new Port configuration at the beginning of the file
    sed -i "1i Port ${Zato_Port_SSH}" /etc/ssh/sshd_config

    log_verbose "SSH port configuration:"
    if $is_verbose; then
        grep -n "Port" /etc/ssh/sshd_config 2>/dev/null || echo "No Port configuration found"
    fi
fi

# Create directory structure
log_verbose "Creating directory structure"
mkdir -p ${Zato_Env_Path}
chown zato:zato ${Zato_Env_Path}

# MODIFIED
if [ ! -d "${Zato_Env_Path}/server1" ]; then
    log_timestamp "Criando ambiente Zato do zero (Primeira execução)..."

    QUICKSTART_EXTRA_ARGS=""
    if [ ! -z "$Zato_Admin_Invoke_Password" ]; then
        QUICKSTART_EXTRA_ARGS="--server-api-client-for-scheduler-password '$Zato_Admin_Invoke_Password'"
    fi

    quickstart_output=$(su - zato -c "export PATH=\$PATH:~/current/bin && \
        export PYTHONWARNINGS=ignore && \
        export Zato_Start_Pubsub=${Zato_Start_Pubsub} && \
        export Zato_Start_Load_Balancer=${Zato_Start_Load_Balancer} && \
        export Zato_Metrics_Password='${Zato_Metrics_Password}' && \
        Zato_Server_To_Scheduler_Use_TLS=False zato quickstart \
        ${Zato_Env_Path} \
        --odb-type sqlite \
        --cluster-name '${Zato_Cluster_Name}' \
        ${QUICKSTART_EXTRA_ARGS} \
        --verbose" 2>&1)
    if [ $? -ne 0 ]; then
        log_timestamp "Failed to create a quickstart environment"
        echo "$quickstart_output"
        exit 1
    fi
else
    log_timestamp "Ambiente Zato já existe. Pulando a construção para iniciar mais rápido!"
fi


# Add PYTHONWARNINGS to zato user's .bashrc to silence warnings in future sessions
if ! grep -q "PYTHONWARNINGS" /opt/zato/.bashrc; then
    echo "export PYTHONWARNINGS=ignore" >> /opt/zato/.bashrc
fi

# Add GEVENT_SUPPORT to zato user's .bashrc to enable gevent support in debugpy
if ! grep -q "GEVENT_SUPPORT" /opt/zato/.bashrc; then
    echo "export GEVENT_SUPPORT=True" >> /opt/zato/.bashrc
fi

# Start SSH service silently
log_verbose "Starting SSH"
service ssh start >&3 2>&4 || log_timestamp "Failed to start SSH"

# Ensure server directory exists
if [ ! -d "${Zato_Env_Path}/server1" ]; then
    log_timestamp "ERROR: Server directory ${Zato_Env_Path}/server1 was not created properly"
    log_timestamp "Check Zato quickstart command output for errors"
    exit 1
fi

# Set Zato Dashboard password - suppressing the "Changing password" output
log_verbose "Configuring Zato Dashboard and IDE"
su - zato -c "export PYTHONWARNINGS=ignore && /opt/zato/current/bin/zato update password ${Zato_Env_Path}/web-admin admin --password \"$ZATO_DASHBOARD_PASSWORD\" $VERBOSE_FLAG" >&3 2>&4

# Create startup scripts from template
log_verbose "Creating startup scripts from template"
for component in "server1" "web-admin" "load-balancer" "scheduler"; do
    cp /opt/zato/start-template.sh ${Zato_Env_Path}/start-${component}-fg.sh
    sed -i "s|COMPONENT_PATH|${Zato_Env_Path}/${component}|g" ${Zato_Env_Path}/start-${component}-fg.sh
    # Add PYTHONWARNINGS to startup scripts
    sed -i "2i export PYTHONWARNINGS=ignore" ${Zato_Env_Path}/start-${component}-fg.sh
    chown zato:zato ${Zato_Env_Path}/start-${component}-fg.sh
    chmod 764 ${Zato_Env_Path}/start-${component}-fg.sh
done

# Update all Zato environment variables in startup scripts
for script in ${Zato_Env_Path}/start-*.sh; do
    if [[ -f "$script" ]]; then
        add_zato_vars_to_file "$script"
    fi
done

# Update port configurations in Zato config files
if [ -d "${Zato_Env_Path}/web-admin" ]; then
    # Update web admin port (default 8183)
    update_zato_port_config "${Zato_Env_Path}/web-admin/config/repo/web-admin.conf" "8183" "${Zato_Port_Dashboard}" "Web Admin"
fi

if [ -d "${Zato_Env_Path}/server1" ]; then
    # Update server port (default 17010)
    update_zato_port_config "${Zato_Env_Path}/server1/config/repo/server.conf" "17010" "${Zato_Port_Server}" "Server"
fi

if [ -d "${Zato_Env_Path}/load-balancer" ]; then
    # Update load balancer port (default 11223)
    update_zato_port_config "${Zato_Env_Path}/load-balancer/config/repo/lb-agent.conf" "11223" "${Zato_Port_Load_Balancer}" "Load Balancer"
fi

# Create extra directories
log_verbose "Creating extra directories"
mkdir -p /tmp/zato-user-conf/
mkdir -p /opt/hot-deploy/user-conf/
chown -R zato:zato /opt/hot-deploy/user-conf/
chown -R zato:zato /tmp/zato-user-conf/

# Add useful commands to bash history
log_verbose "Setting up bash history for users"

echo "su - zato" >> /root/.bash_history
echo "tail ~zato/env/qs-1/server1/logs/server.log" >> /root/.bash_history
echo "cat ~zato/env/qs-1/server1/logs/server.log" >> /root/.bash_history

echo "tail -f ~zato/env/qs-1/server1/logs/server.log" >> ~zato/.bash_history
echo "cat ~zato/env/qs-1/server1/logs/server.log" >> ~zato/.bash_history

chown zato:zato ~zato/.bash_history

# Configure vim settings for both users
log_verbose "Setting up vim configuration"
echo ":set tabstop=4" > /opt/zato/.vimrc
echo ":set shiftwidth=4" >> /opt/zato/.vimrc
echo ":set expandtab" >> /opt/zato/.vimrc
echo ":set noincsearch" >> /opt/zato/.vimrc
chown zato:zato /opt/zato/.vimrc

echo ":set tabstop=4" > /root/.vimrc
echo ":set shiftwidth=4" >> /root/.vimrc
echo ":set expandtab" >> /root/.vimrc
echo ":set noincsearch" >> /root/.vimrc

# Add bash settings to bashrc files
log_verbose "Adding bash settings to bashrc files"
echo "bind 'set enable-bracketed-paste off'" >> /opt/zato/.bashrc
echo "source /usr/share/mc/bin/mc.sh" >> /opt/zato/.bashrc
echo "export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt" >> /opt/zato/.bashrc
echo "export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt" >> /opt/zato/.bashrc

echo "bind 'set enable-bracketed-paste off'" >> /root/.bashrc
echo "source /usr/share/mc/bin/mc.sh" >> /root/.bashrc
echo "export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt" >> /root/.bashrc
echo "export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt" >> /root/.bashrc

# Also update .bashrc with all Zato environment variables
log_verbose "Updating Zato user bashrc with environment variables"

# Create a backup of the original .bashrc
cp /opt/zato/.bashrc /opt/zato/.bashrc.bak

# Remove existing Zato exports
sed -i '/^export Zato_/d' /opt/zato/.bashrc
sed -i '/^# Dynamically added Zato environment variables/d' /opt/zato/.bashrc

# Add all Zato environment variables
add_zato_vars_to_file "/opt/zato/.bashrc"

# Make sure permissions are correct
chown zato:zato /opt/zato/.bashrc

# Install Python requirements if they exist
if [ -f "/opt/hot-deploy/python-reqs/requirements.txt" ]; then
    log_verbose "Installing Python requirements from /opt/hot-deploy/python-reqs/requirements.txt"

    # Check if any proxy environment variables are set
    proxy_option=""
    proxy_source=""
    for proxy_var in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy; do
        proxy_value=$(printenv "$proxy_var")
        if [ ! -z "$proxy_value" ]; then
            log_verbose "Using proxy from $proxy_var: $proxy_value"
            proxy_option="--proxy $proxy_value"
            proxy_source="$proxy_var"
            break
        fi
    done

    # Run pip with or without proxy option
    if [ ! -z "$proxy_option" ]; then
        log_verbose "Running pip install with proxy option: $proxy_option ($proxy_source)"
        su - zato -c "export PYTHONWARNINGS=ignore && /opt/zato/current/bin/pip install --disable-pip-version-check $proxy_option -r /opt/hot-deploy/python-reqs/requirements.txt"
    else
        log_verbose "Running pip install without proxy"
        su - zato -c "export PYTHONWARNINGS=ignore && /opt/zato/current/bin/pip install --disable-pip-version-check -r /opt/hot-deploy/python-reqs/requirements.txt"
    fi
fi

# Run custom scripts before server start
run_custom_scripts "before-server-started"

# Create logrotate config for zato logs
cat > /etc/logrotate.d/zato-logs << 'EOF'
/opt/zato/env/qs-1/server1/logs/load-balancer.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

# Run internal startup scripts if the directory exists
if [ -d "/opt/hot-deploy/zato-internal" ]; then
    for script in $(ls /opt/hot-deploy/zato-internal/*.sh 2>/dev/null | sort); do
        if [ -f "$script" ]; then
            log_timestamp "Running script: $script"
            bash "$script" || true
        fi
    done
fi

# Run custom startup script if it exists
if [ -f "/opt/hot-deploy/startup.sh" ]; then
    log_timestamp "Running startup script"
    bash /opt/hot-deploy/startup.sh || true
fi

# =================================================================
# INÍCIO DA DIETA MOUNJARO (CONTROLE DE CONSUMO)
# =================================================================

log_timestamp "Starting scheduler"
sudo -u zato env $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy|^SSL_CERT_FILE|^REQUESTS_CA_BUNDLE') PYTHONWARNINGS=ignore bash ${Zato_Env_Path}/start-scheduler-fg.sh >&3 2>&4 &

# --- DIETA MOUNJARO: Queue Bridge Opcional ---
if [ "$Zato_Start_Queue_Bridge" = "True" ] || [ "$Zato_Start_Queue_Bridge" = "true" ]; then
    log_timestamp "Starting queue bridge"
    sudo -u zato env $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy|^SSL_CERT_FILE|^REQUESTS_CA_BUNDLE') PYTHONWARNINGS=ignore bash -c "cd ~/4.1 && make queue-bridge" >&3 2>&4 &
else
    log_timestamp "Mounjaro: Queue Bridge (AMQP/IBM MQ) desativado."
fi


# --- DIETA MOUNJARO: Redução de Workers ---
if [ -n "$Zato_Workers" ]; then
    log_timestamp "Mounjaro: Reduzindo Gunicorn Workers do Server1 para ${Zato_Workers}"
    sed -i "s/^gunicorn_workers =.*/gunicorn_workers = ${Zato_Workers}/g" ${Zato_Env_Path}/server1/config/repo/server.conf
fi

log_timestamp "Starting server"
sudo -u zato env $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy|^SSL_CERT_FILE|^REQUESTS_CA_BUNDLE') PYTHONWARNINGS=ignore bash ${Zato_Env_Path}/start-server1-fg.sh >&3 2>&4 &

# --- DIETA MOUNJARO: Dashboard Opcional ---
if [ "$Zato_Start_Web_Admin" = "True" ] || [ "$Zato_Start_Web_Admin" = "true" ]; then
    if [ -n "$Zato_Workers" ]; then
        sed -i "s/^gunicorn_workers =.*/gunicorn_workers = ${Zato_Workers}/g" ${Zato_Env_Path}/web-admin/config/repo/web-admin.conf
    fi
    log_timestamp "Starting dashboard"
    sudo -u zato env $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy|^SSL_CERT_FILE|^REQUESTS_CA_BUNDLE') PYTHONWARNINGS=ignore bash ${Zato_Env_Path}/start-web-admin-fg.sh >&3 2>&4 &
else
    log_timestamp "Mounjaro: Dashboard Web desativado para economizar RAM."
fi

# HAProxy Configs
su - zato -c "cp ~/current/zato-common/src/zato/common/pubsub/server/haproxy.cfg ~/env/qs-1/haproxy.cfg" 2>&1 | while read line; do log_timestamp "Copy output: $line"; done
su - zato -c "envsubst < ~/env/qs-1/haproxy.cfg > ~/env/qs-1/haproxy.cfg.tmp && mv ~/env/qs-1/haproxy.cfg.tmp ~/env/qs-1/haproxy.cfg" 2>&1 | while read line; do log_timestamp "Envsubst output: $line"; done

cp /blocked-paths.txt /opt/zato/env/qs-1/blocked-paths.txt
chown zato:ubuntu /opt/zato/env/qs-1/blocked-paths.txt

create_startup_script "start-haproxy.sh" "haproxy -db -f ~/env/qs-1/haproxy.cfg > ~/env/qs-1/server1/logs/haproxy.log 2>&1"

# SSL Configs
mkdir -p /opt/hot-deploy/ssl
chown zato:ubuntu /opt/hot-deploy/ssl
chmod 750 /opt/hot-deploy/ssl

if [ -f /opt/hot-deploy/ssl/zato.pem ]; then
    cp /opt/hot-deploy/ssl/zato.pem /opt/hot-deploy/ssl/user.pem
    chmod 400 /opt/hot-deploy/ssl/user.pem
    chown zato:zato /opt/hot-deploy/ssl/user.pem
    log_timestamp "Using SSL certificate from /opt/hot-deploy/ssl/zato.pem"
fi

log_verbose "Generating SSL certificate"
sudo -u zato env $(printenv | grep -E '^Zato_') bash /generate-cert.sh >&3 2>&4

log_verbose "Configuring HAProxy SSL"
sudo -u zato env $(printenv | grep -E '^Zato_') /opt/zato/current/bin/py /sslconfig.py >&3 2>&4

# --- DIETA MOUNJARO: Load Balancer Opcional ---
if [ "$Zato_Start_Load_Balancer" = "True" ] || [ "$Zato_Start_Load_Balancer" = "true" ]; then
    log_timestamp "Starting load balancer (HAProxy)"
    sudo -u zato env $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy|^SSL_CERT_FILE|^REQUESTS_CA_BUNDLE') PYTHONWARNINGS=ignore bash /opt/zato/env/qs-1/start-haproxy.sh &
    log_verbose "Starting Zato load balancer agent"
    sudo -u zato env $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy|^SSL_CERT_FILE|^REQUESTS_CA_BUNDLE') PYTHONWARNINGS=ignore bash ${Zato_Env_Path}/start-load-balancer-fg.sh >&3 2>&4 &
else
    log_timestamp "Mounjaro: Load Balancer e HAProxy nativo desativados."
fi

log_timestamp "Starting rule engine"

# Wait for server to be available
log_verbose "Waiting for Zato server to become available"
for i in {1..60}; do
  if [ $i -eq 20 ]; then log_verbose "Starting server (2)"; fi;
  response=$(curl -s "http://localhost:${Zato_Port_Server}/zato/ping" 2>/dev/null);
  if [[ "$response" == *'"is_ok":true'* ]]; then break; fi;
  sleep 1;
done

# Get the actual Zato version directly from the command output
Zato_Version=$(su - zato -c "zato --version 2>/dev/null" | tr -d '\n')

run_custom_scripts "after-server-started"

# --- DIETA MOUNJARO: File Listeners Opcionais ---
if [ "$Zato_Start_File_Listener" = "True" ] || [ "$Zato_Start_File_Listener" = "true" ]; then
    log_timestamp "Starting file pickup listener"
    sudo -u zato env $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy|^SSL_CERT_FILE|^REQUESTS_CA_BUNDLE' | grep -v '^Zato_Version=') PYTHONWARNINGS=ignore bash -c "cd ~/4.1 && make file-pickup-listener" >&3 2>&4 &

    for var in $(printenv | grep '^Zato_Project_Root' | sort); do
        var_name=$(echo "$var" | cut -d= -f1)
        var_value=$(echo "$var" | cut -d= -f2-)

        if [ ! -z "$var_value" ]; then
            log_timestamp "Starting file transfer listener for ${var_name}: ${var_value}"
            script_name="start-file-transfer-listener-${var_name}.sh"
            create_startup_script "${script_name}" "~/current/bin/py ~/4.1/code/zato-common/src/zato/common/file_transfer/listener.py \"${var_value}\" > ~/env/qs-1/server1/logs/file_transfer_listener_${var_name}.log 2>&1"
            sudo -u zato bash -c "
                export PYTHONWARNINGS=ignore
                $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy|^SSL_CERT_FILE|^REQUESTS_CA_BUNDLE' | grep -v '^Zato_Version=' | sed 's/^/export /' | sed 's/=/=\"/' | sed 's/$/\"/')
                bash /opt/zato/env/qs-1/${script_name}
            " &
        fi
    done

    env_ini_file=$(find /opt/hot-deploy -name "env.ini" -type f 2>/dev/null | head -n 1)
    if [ ! -z "$env_ini_file" ]; then
        log_timestamp "Processing env.ini at ${env_ini_file} for Zato_Project_Root paths"
        while IFS='=' read -r key value; do
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            if [[ "$key" =~ ^Zato_Project_Root ]]; then
                if [ ! -z "$value" ]; then
                    log_timestamp "Starting file transfer listener for env_ini_${key}: ${value}"
                    script_name="start-file-transfer-listener-env_ini_${key}.sh"
                    create_startup_script "${script_name}" "~/current/bin/py ~/4.1/code/zato-common/src/zato/common/file_transfer/listener.py \"${value}\" > ~/env/qs-1/server1/logs/file_transfer_listener_env_ini_${key}.log 2>&1"
                    sudo -u zato bash -c "
                        export PYTHONWARNINGS=ignore
                        $(printenv | grep -E '^Zato_|^HTTP_|^HTTPS_|^http_|^https_|^NO_PROXY|^no_proxy' | grep -v '^Zato_Version=' | sed 's/^/export /' | sed 's/=/=\"/' | sed 's/$/\"/')
                        bash /opt/zato/env/qs-1/${script_name}
                    " &
                fi
            fi
        done < "$env_ini_file"
    fi
else
    log_timestamp "Mounjaro: File Transfer e Pickup Listeners desativados."
fi

# Always show version information
echo -e "\e[36m[$(get_timestamp)]\e[0m \e[32mVersion: ${Zato_Version}\e[0m"

# Show environment name if provided
if [ -n "$Zato_Env_Name" ]; then
    echo -e "\e[36m[$(get_timestamp)]\e[0m \e[32mEnvironment: ${Zato_Env_Name}\e[0m"
fi

# Force this message to display
echo -e "\e[36m[$(get_timestamp)]\e[0m \e[32mContainer ready ⭐\e[0m"
echo -e "\e[36m[$(get_timestamp)]\e[0m \e[32m(Ctrl+C to exit)\e[0m"

# Run post-server operations in the background
perform_post_server_operations &

# Setup cron jobs for pub/sub message expiration cleanup ONLY
sudo -u zato bash -c "
    mkdir -p ~/env/qs-1/server1/logs
    (crontab -l 2>/dev/null | grep -v 'pubsub/cleanup.py'; \
     echo '*/5 * * * * ~/current/bin/py ~/current/zato-common/src/zato/common/pubsub/cleanup.py --once >> ~/env/qs-1/server1/logs/pubsub-cleanup.log 2>&1') | crontab -
"

# Keep container running and show server logs
tail -f -n 2000 ${Zato_Env_Path}/server1/logs/server.log || true