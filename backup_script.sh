#!/bin/bash

cd "$(dirname "$0")" || exit 1

# MikroTik Configuration Backup Script
# This script connects to MikroTik routers/switches, exports configurations,
# and pushes them to a git repository

# Configuration variables
USERNAME="mikrotik-backup-user"     # Default MikroTik username
SSH_PORT="22"                       # Default SSH port
SSH_KEY_PATH=""                     # Path to SSH private key (optional, uses default ~/.ssh/.. if empty)

# Logging
LOG_FILE="/var/log/mikrotik/backup.log"
LOG_RETENTION_DAYS=7   # Keep N days worth of logs

# SMTP Configuration for notifications
## Note- I never finished implementing AND testing SMTP.
SMTP_ENABLED=false              # Enable/disable email notifications
SMTP_SERVER="relay.local.xtremeownage.com"         # SMTP server address
SMTP_PORT="25"                 # SMTP server port (587 for TLS, 25 for plain)
SMTP_USERNAME=""                # SMTP username (leave empty for no auth)
SMTP_PASSWORD=""                # SMTP password (leave empty for no auth)
SMTP_FROM="mikrotik-backup@xtremeownage.com"  # From email address
SMTP_TO="admin@yourdomain.com"     # To email address
SMTP_USE_TLS=false              # Use TLS/STARTTLS
SMTP_NOTIFY="always"            # When to send emails: "always", "error", "success", "never"

# Export commands to run - first command keeps headers, subsequent commands have headers stripped
EXPORT_COMMANDS=(
    "/export show-sensitive terse verbose"
    "/user/export show-sensitive terse verbose"
    "/system/scheduler/export show-sensitive terse verbose" 
    "/queue/export show-sensitive terse verbose"
)

# Array of MikroTik device IPs - Add your device IPs here
MIKROTIK_IPS=(
    "10.100.0.100"
    "10.100.0.200"
    "10.100.0.15"
    #"10.100.0.20"
    "10.102.14.2"
    # Add more IPs as needed
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging helper
log() {
    local level=$1
    local color=$2
    local msg=$3
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${color}[${level}]${NC} $msg"
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
}

print_status()  { log "INFO"    "$BLUE"   "$1"; }
print_success() { log "SUCCESS" "$GREEN"  "$1"; }
print_warning() { log "WARNING" "$YELLOW" "$1"; }
print_error()   { log "ERROR"   "$RED"    "$1"; }

# Trap unexpected failures and log them directly to file
trap 'echo "[$(date "+%Y-%m-%d %H:%M:%S")] [ERROR] Unexpected failure on line $LINENO (exit code $?)" >> "$LOG_FILE"' ERR

# Function to check if required tools are installed
check_dependencies() {
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed. Please install git and run the script again."
        exit 1
    fi
    
    # Check for mail command if SMTP is enabled
    if [ "$SMTP_ENABLED" = true ] && ! command -v mail &> /dev/null && ! command -v sendmail &> /dev/null; then
        print_warning "No mail command found. Email notifications will be disabled."
        print_warning "Install mailutils or postfix to enable email notifications."
        SMTP_ENABLED=false
    fi
}

# Function to setup git repository
setup_git_repo() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "This script must be run from within a git repository"
        print_error "Initialize git repo first: git init && git remote add origin <your-repo-url>"
        exit 1
    fi
    
    print_status "Pulling latest changes from remote..."
    git pull 2>/dev/null || print_warning "Could not pull from remote (this is normal for first run)"
}

# Function to build SSH command with proper options
build_ssh_cmd() {
    local ip=$1
    local ssh_cmd="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
    
    # Add SSH key if specified
    if [ -n "$SSH_KEY_PATH" ]; then
        ssh_cmd="$ssh_cmd -i $SSH_KEY_PATH"
    fi
    
    # Add port and user@host
    ssh_cmd="$ssh_cmd -p $SSH_PORT $USERNAME@$ip"
    
    echo "$ssh_cmd"
}

# Function to get device identity (just use IP address)
get_device_identity() {
    local ip=$1
    echo $ip
}

# Function to export configuration from MikroTik device
export_config() {
    local ip=$1
    local device_name=$2
    local device_dir="./$device_name"
    local config_file="$device_dir/config.rsc"
    local ssh_cmd
    local temp_file
    local first_command=true
    
    print_status "Exporting configuration from $ip ($device_name)..."
    
    # Create device directory if it doesn't exist
    mkdir -p "$device_dir"
    
    # Build SSH command with proper timeout for config export
    ssh_cmd=$(build_ssh_cmd "$ip")
    ssh_cmd=${ssh_cmd/ConnectTimeout=10/ConnectTimeout=30}
    
    # Initialize the config file
    > "$config_file"
    
    # Run each export command
    for cmd in "${EXPORT_COMMANDS[@]}"; do
        temp_file=$(mktemp)
        
        print_status "Running: $cmd"
        $ssh_cmd "$cmd" > "$temp_file" 2>/dev/null

        # Strip RouterOS auto-generated date/comment header
        sed -i '/^# [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} .* by RouterOS /d' "$temp_file"        

        if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
            if [ "$first_command" = true ]; then
                # First command: include everything (headers and content)
                cat "$temp_file" >> "$config_file"
                first_command=false
            else
                # Subsequent commands: skip comment lines at the beginning
                awk '
                BEGIN { in_header = 1 }
                /^#/ { 
                    if (in_header) next
                    else print
                }
                !/^#/ { 
                    in_header = 0
                    print 
                }' "$temp_file" >> "$config_file"
            fi
            print_success "✓ $cmd completed"
        else
            print_warning "✗ $cmd failed or returned no data"
        fi
        
        rm -f "$temp_file"
    done
    
    # Check if we got any content
    if [ -s "$config_file" ]; then
        # Create device info file
        cat > "$device_dir/device_info.txt" << EOF
Device IP: $ip
Device Name: $device_name
Last Backup: $(date)
SSH Port: $SSH_PORT
SSH Key: ${SSH_KEY_PATH:-"Default SSH key"}
Export Commands: ${#EXPORT_COMMANDS[@]} commands executed
EOF
        
        print_success "All configurations exported successfully for $device_name"
        return 0
    else
        print_error "Failed to export any configuration from $ip"
        rm -f "$config_file"  # Remove empty file
        return 1
    fi
}

# Function to commit and push to git
git_commit_and_push() {
    print_status "Committing and pushing changes to git repository..."
    
    # Add all changes
    git add .
    
    # Check if there are changes to commit
    if git diff --staged --quiet; then
        print_warning "No changes to commit"
        return 0
    fi
    
    # Commit changes
    local commit_message="Automated backup - $(date '+%Y-%m-%d %H:%M:%S')"
    git commit -m "$commit_message"
    
    if [ $? -eq 0 ]; then
        # Push to remote repository - handle upstream branch setup
        git push 2>/dev/null || git push --set-upstream origin $(git branch --show-current) || {
            print_error "Failed to push to remote repository"
            return 1
        }
        print_success "Changes pushed to remote repository successfully"
    else
        print_error "Failed to commit changes"
        return 1
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    local device_dir=$1
    
    print_status "Cleaning up old backups in $device_dir..."
    
    # Keep only the most recent backup files (excluding latest_config.rsc)
    find "$device_dir" -name "config_*.rsc" -type f | sort | head -n -${BACKUP_RETENTION} | xargs -r rm
}

# Main function
main() {
    # Rotate logs
    if [ -f "$LOG_FILE" ]; then
        ts=$(date '+%Y-%m-%d_%H-%M-%S')
        mv "$LOG_FILE" "${LOG_FILE%.log}_$ts.log"
    fi
    touch "$LOG_FILE"

    # Cleanup old logs
    find "$(dirname "$LOG_FILE")" -maxdepth 1 -name "$(basename "${LOG_FILE%.log}")_*.log"         -type f -mtime +$LOG_RETENTION_DAYS -exec rm -f {} \;

    print_status "Starting MikroTik configuration backup script..."
    
    local start_time=$(date)
    local failed_devices=()
    local success_devices=()
    
    # Check dependencies
    check_dependencies
    
    # Validate that we have devices to backup
    if [ ${#MIKROTIK_IPS[@]} -eq 0 ]; then
        print_error "No MikroTik IPs defined in the MIKROTIK_IPS array"
        exit 1
    fi
    
    # Check SSH key if specified
    if [ -n "$SSH_KEY_PATH" ] && [ ! -f "$SSH_KEY_PATH" ]; then
        print_error "SSH key file not found: $SSH_KEY_PATH"
        exit 1
    fi
    
    # Setup git repository
    setup_git_repo
    
    local success_count=0
    local total_count=${#MIKROTIK_IPS[@]}
    
    # Process each MikroTik device
    for ip in "${MIKROTIK_IPS[@]}"; do
        print_status "Processing device: $ip"
        
        # Get device identity (just use IP)
        device_name=$(get_device_identity "$ip")
        print_status "Using device folder: $device_name"
        
        # Export configuration
        if export_config "$ip" "$device_name"; then
            success_devices+=("$ip")
            ((success_count++))
        else
            failed_devices+=("$ip")
        fi
        
        echo "----------------------------------------"
    done
    
    # Commit and push if we had any successful exports
    local git_success=false
    if [ $success_count -gt 0 ]; then
        if git_commit_and_push; then
            git_success=true
        fi
    fi
    
    local end_time=$(date)
    
    print_status "Backup completed!"
    print_status "Successfully backed up $success_count out of $total_count devices"
    
    # Prepare email notification
    local email_subject
    local email_body
    local email_status
    
    if [ $success_count -eq $total_count ] && [ "$git_success" = true ]; then
        # Complete success
        email_status="success"
        email_subject="✅ MikroTik Backup - All devices successful ($success_count/$total_count)"
        email_body="MikroTik configuration backup completed successfully.

📊 BACKUP SUMMARY:
- Total devices: $total_count
- Successful: $success_count
- Failed: $((total_count - success_count))
- Git push: ✅ Success

🔧 SUCCESSFUL DEVICES:
$(printf '%s\n' "${success_devices[@]}")

⏰ TIMING:
- Started: $start_time
- Completed: $end_time"
    else
        # Partial or complete failure
        email_status="error"
        email_subject="❌ MikroTik Backup - Issues detected ($success_count/$total_count successful)"
        email_body="MikroTik configuration backup completed with issues.

📊 BACKUP SUMMARY:
- Total devices: $total_count
- Successful: $success_count
- Failed: $((total_count - success_count))
- Git push: $([ "$git_success" = true ] && echo "✅ Success" || echo "❌ Failed")

✅ SUCCESSFUL DEVICES:
$(printf '%s\n' "${success_devices[@]}")

❌ FAILED DEVICES:
$(printf '%s\n' "${failed_devices[@]}")

⏰ TIMING:
- Started: $start_time
- Completed: $end_time

Please check the logs and device connectivity for failed devices."
    fi
    
    # Send email notification
    send_email "$email_subject" "$email_body" "$email_status"
    
    if [ $success_count -eq $total_count ] && [ "$git_success" = true ]; then
        exit 0
    else
        exit 1
    fi
}

# Script usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -u, --username USERNAME   Set SSH username (default: admin)"
    echo "  -p, --port PORT          Set SSH port (default: 22)"
    echo "  -k, --key PATH           Path to SSH private key file"
    echo ""
    echo "Before running the script:"
    echo "1. Place this script in the root of your git repository"
    echo "2. Add your MikroTik device IPs to the MIKROTIK_IPS array in the script"
    echo "3. Ensure SSH key authentication is set up on all MikroTik devices"
    echo ""
    echo "SSH Key Setup:"
    echo "1. Generate SSH key: ssh-keygen -t rsa -b 2048 -f ~/.ssh/mikrotik_key"
    echo "2. Copy public key to MikroTik: /user ssh-keys import public-key-file=mikrotik_key.pub user=admin"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -k|--key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run the main function
main
