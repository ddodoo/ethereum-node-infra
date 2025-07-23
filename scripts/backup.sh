#!/bin/bash

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
GETH_DATA_DIR="${GETH_DATA_DIR:-$PROJECT_ROOT/data/geth}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAX_BACKUP_SIZE_GB="${MAX_BACKUP_SIZE_GB:-50}"  # Alert if backup exceeds this size

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to check available disk space
check_disk_space() {
    local required_space_gb="$1"
    local available_space_kb=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))
    
    if [ $available_space_gb -lt $required_space_gb ]; then
        error "Insufficient disk space. Available: ${available_space_gb}GB, Required: ${required_space_gb}GB"
        return 1
    else
        info "Disk space check passed. Available: ${available_space_gb}GB"
        return 0
    fi
}

# Function to detect correct container name
detect_geth_container() {
    # Try different possible container names
    local possible_names=("geth-node" "ethereum-geth" "geth" "scripts-geth-1" "scripts_geth_1")
    
    for name in "${possible_names[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "^${name}$"; then
            echo "$name"
            return 0
        fi
    done
    
    # Try to find any container with geth in the name
    local geth_container=$(docker ps --format "table {{.Names}}" | grep -i geth | head -1)
    if [ -n "$geth_container" ]; then
        echo "$geth_container"
        return 0
    fi
    
    return 1
}

# Function to check if Geth is syncing
check_geth_sync_status() {
    local container_name="$1"
    
    # Try IPC first
    local sync_status=$(docker exec "$container_name" geth attach --exec "eth.syncing" 2>/dev/null || echo "")
    
    # If IPC fails, try HTTP RPC
    if [ -z "$sync_status" ] || [[ "$sync_status" == *"Fatal"* ]]; then
        sync_status=$(docker exec "$container_name" sh -c 'curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}" http://localhost:8545 2>/dev/null | grep -o "\"result\":[^,}]*" | cut -d: -f2' 2>/dev/null || echo "null")
    fi
    
    if [ "$sync_status" != "false" ] && [ "$sync_status" != "null" ] && [[ "$sync_status" != *"false"* ]]; then
        warn "Geth is currently syncing. This may affect backup consistency."
        return 1
    else
        info "Geth sync status: ready for backup"
        return 0
    fi
}

# Function to get Geth block number
get_geth_block_number() {
    local container_name="$1"
    
    # Try different methods to get block number
    local block_number=""
    
    # Method 1: Try IPC socket
    block_number=$(docker exec "$container_name" geth attach --exec "eth.blockNumber" 2>/dev/null || echo "")
    if [[ "$block_number" =~ ^[0-9]+$ ]]; then
        echo "$block_number"
        return 0
    fi
    
    # Method 2: Try HTTP RPC if available
    block_number=$(docker exec "$container_name" sh -c 'curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" http://localhost:8545 2>/dev/null | grep -o "\"result\":\"[^\"]*\"" | cut -d\" -f4' 2>/dev/null || echo "")
    if [[ "$block_number" =~ ^0x[0-9a-fA-F]+$ ]]; then
        # Convert hex to decimal
        echo $((block_number))
        return 0
    fi
    
    # Method 3: Use timestamp as fallback
    echo "unknown_$(date +%s)"
    return 0
}

# Function to detect Geth data directory in container
detect_container_geth_data() {
    local container_name="$1"
    
    # Common Geth data paths in container
    local possible_paths=(
        "/root/.ethereum"
        "/data"
        "/ethereum-data"
        "/geth-data"
    )
    
    for path in "${possible_paths[@]}"; do
        if docker exec "$container_name" test -d "$path" 2>/dev/null; then
            # Check if it contains Geth data
            if docker exec "$container_name" test -d "$path/geth" 2>/dev/null || \
               docker exec "$container_name" test -f "$path/LOCK" 2>/dev/null; then
                echo "$path"
                return 0
            fi
        fi
    done
    
    # Try to find any directory with 'geth' or 'chaindata'
    local geth_path=$(docker exec "$container_name" find / -name "chaindata" -type d 2>/dev/null | head -1)
    if [ -n "$geth_path" ]; then
        echo "$(dirname "$geth_path")"
        return 0
    fi
    
    return 1
}

# Function to create Geth snapshot backup with improved error handling
backup_geth_snapshot() {
    log "Starting Geth snapshot backup..."
    
    local container_name
    if container_name=$(detect_geth_container); then
        log "Found Geth container: $container_name"
        
        # Check sync status
        check_geth_sync_status "$container_name" || warn "Proceeding with backup despite sync status"
        
        # Get current block number for backup metadata
        local current_block=$(get_geth_block_number "$container_name")
        # Clean the block number to remove any error messages or invalid characters
        current_block=$(echo "$current_block" | sed 's/[^0-9a-zA-Z_]/_/g' | head -c 20)
        info "Current block identifier: $current_block"
        
        # Check disk space (estimate 20GB for Geth data)
        if ! check_disk_space 25; then
            return 1
        fi
        
        local container_data_path
        if container_data_path=$(detect_container_geth_data "$container_name"); then
            log "Found Geth data in container at: $container_data_path"
            
            local backup_file="$BACKUP_DIR/geth_snapshot_${TIMESTAMP}_block_${current_block}.tar.gz"
            local temp_backup="$backup_file.tmp"
            
            info "Creating backup archive..."
            if docker exec "$container_name" tar -czf - "$container_data_path" > "$temp_backup" 2>/dev/null; then
                mv "$temp_backup" "$backup_file"
                
                # Verify backup integrity
                if tar -tzf "$backup_file" >/dev/null 2>&1; then
                    log "Backup integrity verified"
                    local backup_size_bytes=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
                    local backup_size_gb=$((backup_size_bytes / 1024 / 1024 / 1024))
                    local backup_size_human=$(du -h "$backup_file" | cut -f1)
                    
                    log "Geth snapshot backup created: $backup_file"
                    log "Backup size: $backup_size_human"
                    
                    # Alert if backup is unusually large
                    if [ $backup_size_gb -gt $MAX_BACKUP_SIZE_GB ]; then
                        warn "Backup size (${backup_size_gb}GB) exceeds expected maximum (${MAX_BACKUP_SIZE_GB}GB)"
                    fi
                    
                    # Create metadata file
                    cat > "$backup_file.meta" <<EOF
backup_type=geth_snapshot
timestamp=$TIMESTAMP
block_number=$current_block
container_name=$container_name
data_path=$container_data_path
size_bytes=$backup_size_bytes
size_human=$backup_size_human
EOF
                    
                    return 0
                else
                    error "Backup integrity check failed"
                    rm -f "$backup_file" "$temp_backup"
                    return 1
                fi
            else
                error "Failed to create container backup"
                rm -f "$temp_backup"
                return 1
            fi
        else
            warn "Could not detect Geth data path in container, trying host volumes..."
            return backup_geth_host_fallback
        fi
    else
        warn "Geth container not found, trying offline backup..."
        return backup_geth_host_fallback
    fi
}

# Fallback function for host-based backup
backup_geth_host_fallback() {
    local data_dir
    if data_dir=$(detect_geth_data_dir); then
        log "Found Geth data directory: $data_dir"
        
        # Check if Geth is using this directory (lockfile check)
        if [ -f "$data_dir/LOCK" ]; then
            warn "Geth appears to be running and using this data directory"
            warn "Backup may be inconsistent. Consider stopping Geth first."
        fi
        
        local backup_file="$BACKUP_DIR/geth_offline_${TIMESTAMP}.tar.gz"
        local temp_backup="$backup_file.tmp"
        
        info "Creating offline backup from host directory..."
        if tar -czf "$temp_backup" -C "$(dirname "$data_dir")" "$(basename "$data_dir")" 2>/dev/null; then
            mv "$temp_backup" "$backup_file"
            log "Offline Geth backup created: $backup_file"
            local backup_size=$(du -h "$backup_file" | cut -f1)
            log "Backup size: $backup_size"
            return 0
        else
            error "Failed to create offline Geth backup"
            rm -f "$temp_backup"
            return 1
        fi
    else
        warn "No Geth data directory found in any of the expected locations"
        return 1
    fi
}

# Function to detect Geth data directory on host
detect_geth_data_dir() {
    # Possible data directory locations
    local possible_dirs=(
        "$PROJECT_ROOT/data/geth"
        "$PROJECT_ROOT/data/ethereum"
        "$PROJECT_ROOT/data"
        "$SCRIPT_DIR/data/geth"
        "$SCRIPT_DIR/data"
        "/var/lib/ethereum"
        "/opt/ethereum/data"
    )
    
    for dir in "${possible_dirs[@]}"; do
        if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
            # Check if it looks like Geth data
            if [ -d "$dir/geth" ] || [ -f "$dir/LOCK" ] || [ -d "$dir/chaindata" ]; then
                echo "$dir"
                return 0
            fi
        fi
    done
    
    return 1
}

# Function to backup configuration files
backup_configs() {
    log "Backing up configuration files..."
    
    local config_backup="$BACKUP_DIR/configs_${TIMESTAMP}.tar.gz"
    local temp_backup="$config_backup.tmp"
    local files_to_backup=()
    
    # Check which files exist and add them to backup list
    local possible_files=(
        "docker-compose.yml"
        "compose.yml"
        "docker-compose.prod.yml" 
        "docker-compose.override.yml"
        ".env"
        ".env.example"
        "configs"
        "scripts"
        "deploy.sh"
        "prometheus.yml"
        "grafana"
        "alertmanager.yml"
    )
    
    cd "$PROJECT_ROOT"
    
    for file in "${possible_files[@]}"; do
        if [ -e "$file" ]; then
            files_to_backup+=("$file")
            info "Found config file/dir: $file"
        fi
    done
    
    if [ ${#files_to_backup[@]} -eq 0 ]; then
        warn "No configuration files found to backup"
        return 1
    fi
    
    if tar -czf "$temp_backup" "${files_to_backup[@]}" 2>/dev/null; then
        mv "$temp_backup" "$config_backup"
        log "Configuration backup created: $config_backup"
        log "Backed up files: ${files_to_backup[*]}"
        
        # Create metadata
        cat > "$config_backup.meta" <<EOF
backup_type=configurations
timestamp=$TIMESTAMP
files=${files_to_backup[*]}
project_root=$PROJECT_ROOT
EOF
        return 0
    else
        error "Failed to create configuration backup"
        rm -f "$temp_backup"
        return 1
    fi
}

# Function to detect container names for monitoring
detect_monitoring_containers() {
    local prometheus_container=""
    local grafana_container=""
    
    # Find Prometheus container
    for name in "prometheus" "scripts-prometheus-1" "scripts_prometheus_1"; do
        if docker ps --format "table {{.Names}}" | grep -q "^${name}$"; then
            prometheus_container="$name"
            break
        fi
    done
    
    # Find Grafana container  
    for name in "grafana" "scripts-grafana-1" "scripts_grafana_1"; do
        if docker ps --format "table {{.Names}}" | grep -q "^${name}$"; then
            grafana_container="$name"
            break
        fi
    done
    
    echo "$prometheus_container $grafana_container"
}

# Function to backup monitoring data
backup_monitoring() {
    log "Backing up monitoring data..."
    
    local containers
    containers=($(detect_monitoring_containers))
    local prometheus_container="${containers[0]}"
    local grafana_container="${containers[1]}"
    
    # Backup Prometheus data
    if [ -n "$prometheus_container" ]; then
        log "Found Prometheus container: $prometheus_container"
        local prometheus_backup="$BACKUP_DIR/prometheus_${TIMESTAMP}.tar.gz"
        local temp_backup="$prometheus_backup.tmp"
        
        if docker exec "$prometheus_container" tar -czf - /prometheus 2>/dev/null > "$temp_backup"; then
            if [ -s "$temp_backup" ]; then
                mv "$temp_backup" "$prometheus_backup"
                log "Prometheus data backup created: $prometheus_backup"
                local backup_size=$(du -h "$prometheus_backup" | cut -f1)
                log "Prometheus backup size: $backup_size"
            else
                warn "Prometheus backup is empty"
                rm -f "$temp_backup"
            fi
        else
            warn "Failed to backup Prometheus data"
            rm -f "$temp_backup"
        fi
    else
        warn "Prometheus container not found"
    fi
    
    # Backup Grafana data
    if [ -n "$grafana_container" ]; then
        log "Found Grafana container: $grafana_container"
        local grafana_backup="$BACKUP_DIR/grafana_${TIMESTAMP}.tar.gz"
        local temp_backup="$grafana_backup.tmp"
        
        if docker exec "$grafana_container" tar -czf - /var/lib/grafana 2>/dev/null > "$temp_backup"; then
            if [ -s "$temp_backup" ]; then
                mv "$temp_backup" "$grafana_backup"
                log "Grafana data backup created: $grafana_backup"
                local backup_size=$(du -h "$grafana_backup" | cut -f1)
                log "Grafana backup size: $backup_size"
            else
                warn "Grafana backup is empty"
                rm -f "$temp_backup"
            fi
        else
            warn "Failed to backup Grafana data"
            rm -f "$temp_backup"
        fi
    else
        warn "Grafana container not found"
    fi
}

# Function to clean up old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    
    if [ -d "$BACKUP_DIR" ]; then
        local deleted_count=0
        while IFS= read -r -d '' file; do
            info "Deleting old backup: $(basename "$file")"
            rm -f "$file" "${file}.meta" 2>/dev/null  # Also remove metadata files
            ((deleted_count++))
        done < <(find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +${RETENTION_DAYS} -print0 2>/dev/null)
        
        local remaining_count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f 2>/dev/null | wc -l)
        log "Backup cleanup completed. Deleted: $deleted_count, Remaining: $remaining_count"
    fi
}

# Function to show backup status with enhanced information
show_backup_status() {
    log "=== Backup Status ==="
    
    if [ -d "$BACKUP_DIR" ]; then
        log "Backup directory: $BACKUP_DIR"
        local total_backups=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f 2>/dev/null | wc -l)
        log "Total backups: $total_backups"
        
        if [ $total_backups -gt 0 ]; then
            log "Recent backups:"
            find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | \
                sort -rn | head -10 | while read timestamp filepath; do
                local date_str=$(date -d "@${timestamp%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
                local size=$(du -h "$filepath" | cut -f1)
                local backup_type="unknown"
                
                # Determine backup type from filename
                case "$(basename "$filepath")" in
                    *geth_snapshot*) backup_type="Geth Snapshot" ;;
                    *geth_offline*) backup_type="Geth Offline" ;;
                    *configs*) backup_type="Configurations" ;;
                    *prometheus*) backup_type="Prometheus" ;;
                    *grafana*) backup_type="Grafana" ;;
                esac
                
                info "  [$backup_type] $(basename "$filepath") - $date_str ($size)"
            done
        fi
        
        local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        log "Total backup storage used: $total_size"
        
        # Show disk space
        local available_space=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $4}')
        log "Available disk space: $available_space"
    else
        warn "Backup directory does not exist: $BACKUP_DIR"
    fi
}

# Function to verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    info "Verifying backup: $(basename "$backup_file")"
    
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log "✓ Backup integrity check passed"
        return 0
    else
        error "✗ Backup integrity check failed"
        return 1
    fi
}

# Function to restore from backup (placeholder with safety checks)
restore_backup() {
    local backup_file="$1"
    local restore_path="${2:-}"
    
    error "RESTORE FUNCTION IS NOT IMPLEMENTED FOR SAFETY"
    error "Manual restoration required. Backup file: $backup_file"
    warn "Before restoring:"
    warn "1. Stop all containers: docker-compose down"
    warn "2. Backup current data"
    warn "3. Extract backup to appropriate location"
    warn "4. Verify ownership and permissions"
    warn "5. Start containers: docker-compose up -d"
    return 1
}

# Main backup function
main() {
    local start_time=$(date +%s)
    
    log "=== Starting Ethereum Node Backup Process ==="
    log "Timestamp: $(date)"
    log "Project root: $PROJECT_ROOT"
    log "Backup directory: $BACKUP_DIR"
    log "Retention period: $RETENTION_DAYS days"
    
    # Load environment variables if .env file exists
    if [ -f "$PROJECT_ROOT/.env" ]; then
        set -o allexport
        source "$PROJECT_ROOT/.env"
        set +o allexport
        log "Loaded environment variables from .env"
    fi
    
    local backup_success=true
    local error_messages=()
    local success_messages=()
    
    # Perform backups
    log "--- Phase 1: Geth Data Backup ---"
    if backup_geth_snapshot; then
        success_messages+=("Geth snapshot backup")
    else
        backup_success=false
        error_messages+=("Geth snapshot backup failed")
    fi
    
    log "--- Phase 2: Configuration Backup ---"
    if backup_configs; then
        success_messages+=("Configuration backup")
    else
        backup_success=false
        error_messages+=("Configuration backup failed")
    fi
    
    log "--- Phase 3: Monitoring Data Backup ---"
    backup_monitoring || true  # Non-critical, continue on failure
    
    log "--- Phase 4: Cleanup ---"
    cleanup_old_backups
    
    log "--- Phase 5: Status Report ---"
    show_backup_status
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local duration_human=""
    
    if [ $duration -ge 3600 ]; then
        duration_human="${duration}s ($((duration/3600))h $((duration%3600/60))m)"
    elif [ $duration -ge 60 ]; then
        duration_human="${duration}s ($((duration/60))m $((duration%60))s)"
    else
        duration_human="${duration}s"
    fi
    
    log "=== Backup Process Summary ==="
    if [ "$backup_success" = true ]; then
        log "✓ Backup process completed successfully in $duration_human"
        log "✓ Successful components: ${success_messages[*]}"
    else
        error "✗ Backup process completed with errors in $duration_human"
        error "✗ Failed components: ${error_messages[*]}"
        if [ ${#success_messages[@]} -gt 0 ]; then
            log "✓ Successful components: ${success_messages[*]}"
        fi
        exit 1
    fi
}

# Handle script arguments
case "${1:-full}" in
    "geth")
        log "Running Geth-only backup..."
        backup_geth_snapshot
        ;;
    "configs")
        log "Running configuration backup..."
        backup_configs
        ;;
    "monitoring")
        log "Running monitoring backup..."
        backup_monitoring
        ;;
    "cleanup")
        log "Running cleanup..."
        cleanup_old_backups
        ;;
    "status")
        show_backup_status
        ;;
    "verify")
        if [ -n "${2:-}" ]; then
            verify_backup "$2"
        else
            error "Please specify backup file to verify"
            exit 1
        fi
        ;;
    "restore")
        if [ -n "${2:-}" ]; then
            restore_backup "$2" "${3:-}"
        else
            error "Please specify backup file to restore"
            exit 1
        fi
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo "Commands:"
        echo "  full      - Full backup (default)"
        echo "  geth      - Backup only Geth data"
        echo "  configs   - Backup only configuration files"
        echo "  monitoring - Backup only monitoring data"
        echo "  cleanup   - Clean up old backups"
        echo "  status    - Show backup status"
        echo "  verify    - Verify backup integrity"
        echo "  restore   - Restore from backup (placeholder)"
        echo "  help      - Show this help"
        exit 0
        ;;
    "full"|*)
        main
        ;;
esac