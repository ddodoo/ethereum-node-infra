#!/bin/bash

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
GETH_DATA_DIR="${GETH_DATA_DIR:-$PROJECT_ROOT/data/geth}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Container names (updated to match your setup)
GETH_CONTAINER="geth-node"
PROMETHEUS_CONTAINER="prometheus"
GRAFANA_CONTAINER="grafana"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to check if container is running
is_container_running() {
    local container_name="$1"
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        return 0
    else
        return 1
    fi
}

# Function to create Geth snapshot backup
backup_geth_snapshot() {
    log "Starting Geth snapshot backup..."
    
    if is_container_running "$GETH_CONTAINER"; then
        log "Geth is running. Creating online backup..."
        
        local backup_file="$BACKUP_DIR/geth_snapshot_${TIMESTAMP}.tar.gz"
        
        # Create consistent snapshot
        if docker exec "$GETH_CONTAINER" geth attach --exec "debug.setBlockProfileRate(0)" >/dev/null 2>&1; then
            info "Created consistent snapshot point"
            
            # Create compressed backup with progress
            info "Creating backup (this may take a while)..."
            if tar -czf "$backup_file" -C "$(dirname "$GETH_DATA_DIR")" "$(basename "$GETH_DATA_DIR")" 2>/dev/null; then
                log "Geth snapshot backup created: $backup_file"
                
                # Resume normal operations
                docker exec "$GETH_CONTAINER" geth attach --exec "debug.setBlockProfileRate(1)" >/dev/null 2>&1
                
                # Verify backup integrity
                if tar -tzf "$backup_file" >/dev/null 2>&1; then
                    local backup_size=$(du -h "$backup_file" | cut -f1)
                    log "Backup integrity verified. Size: $backup_size"
                    return 0
                else
                    error "Backup integrity check failed"
                    return 1
                fi
            else
                error "Failed to create Geth snapshot backup"
                return 1
            fi
        else
            error "Failed to create consistent snapshot point"
            return 1
        fi
    else
        warn "Geth is not running. Creating offline backup..."
        
        if [ -d "$GETH_DATA_DIR" ]; then
            local backup_file="$BACKUP_DIR/geth_offline_${TIMESTAMP}.tar.gz"
            info "Creating offline backup (this may take a while)..."
            if tar -czf "$backup_file" -C "$(dirname "$GETH_DATA_DIR")" "$(basename "$GETH_DATA_DIR")"; then
                local backup_size=$(du -h "$backup_file" | cut -f1)
                log "Offline Geth backup created: $backup_file (Size: $backup_size)"
                return 0
            else
                error "Failed to create offline Geth backup"
                return 1
            fi
        else
            warn "Geth data directory not found: $GETH_DATA_DIR"
            info "Expected Geth data at: $GETH_DATA_DIR"
            info "Directory structure:"
            ls -la "$(dirname "$GETH_DATA_DIR")" || true
            return 0  # Not critical if Geth data doesn't exist
        fi
    fi
}

# Function to backup configuration files
backup_configs() {
    log "Backing up configuration files..."
    
    local config_backup="$BACKUP_DIR/configs_${TIMESTAMP}.tar.gz"
    local files_to_backup=()
    
    # Check which files exist before trying to back them up
    [ -f "$PROJECT_ROOT/docker-compose.yml" ] && files_to_backup+=("docker-compose.yml")
    [ -f "$PROJECT_ROOT/docker-compose.prod.yml" ] && files_to_backup+=("docker-compose.prod.yml")
    [ -f "$PROJECT_ROOT/.env" ] && files_to_backup+=(".env")
    [ -d "$PROJECT_ROOT/configs" ] && files_to_backup+=("configs")
    
    if [ ${#files_to_backup[@]} -eq 0 ]; then
        warn "No configuration files found to backup"
        info "Checked for: docker-compose.yml, docker-compose.prod.yml, .env, configs/"
        return 0
    fi
    
    info "Backing up: ${files_to_backup[*]}"
    if tar -czf "$config_backup" -C "$PROJECT_ROOT" "${files_to_backup[@]}"; then
        local backup_size=$(du -h "$config_backup" | cut -f1)
        log "Configuration backup created: $config_backup (Size: $backup_size)"
        return 0
    else
        error "Failed to create configuration backup"
        return 1
    fi
}

# Function to backup monitoring data
backup_monitoring() {
    log "Backing up monitoring data..."
    
    # Backup Prometheus data
    if is_container_running "$PROMETHEUS_CONTAINER"; then
        local prometheus_backup="$BACKUP_DIR/prometheus_${TIMESTAMP}.tar.gz"
        info "Creating Prometheus backup..."
        if docker exec "$PROMETHEUS_CONTAINER" tar -czf - /prometheus 2>/dev/null > "$prometheus_backup"; then
            if [ -s "$prometheus_backup" ]; then
                local backup_size=$(du -h "$prometheus_backup" | cut -f1)
                log "Prometheus data backup created: $prometheus_backup (Size: $backup_size)"
            else
                warn "Prometheus backup is empty"
                rm -f "$prometheus_backup"
            fi
        else
            warn "Failed to create Prometheus backup"
        fi
    else
        warn "Prometheus container not running"
    fi
    
    # Backup Grafana data
    if is_container_running "$GRAFANA_CONTAINER"; then
        local grafana_backup="$BACKUP_DIR/grafana_${TIMESTAMP}.tar.gz"
        info "Creating Grafana backup..."
        if docker exec "$GRAFANA_CONTAINER" tar -czf - /var/lib/grafana 2>/dev/null > "$grafana_backup"; then
            if [ -s "$grafana_backup" ]; then
                local backup_size=$(du -h "$grafana_backup" | cut -f1)
                log "Grafana data backup created: $grafana_backup (Size: $backup_size)"
            else
                warn "Grafana backup is empty"
                rm -f "$grafana_backup"
            fi
        else
            warn "Failed to create Grafana backup"
        fi
    else
        warn "Grafana container not running"
    fi
    
    return 0
}

# Function to clean up old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    
    if [ -d "$BACKUP_DIR" ]; then
        local backups_to_delete=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +${RETENTION_DAYS} | wc -l)
        if [ "$backups_to_delete" -gt 0 ]; then
            info "Found $backups_to_delete old backups to remove"
            find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete
        else
            info "No old backups to remove"
        fi
        
        local remaining_count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f | wc -l)
        log "Backup cleanup completed. Remaining backups: $remaining_count"
    else
        warn "Backup directory not found: $BACKUP_DIR"
    fi
}

# Main backup function
main() {
    local start_time=$(date +%s)
    
    log "Starting backup process..."
    info "Backup directory: $BACKUP_DIR"
    
    # Load environment variables if .env file exists
    if [ -f "$PROJECT_ROOT/.env" ]; then
        set -o allexport
        source "$PROJECT_ROOT/.env"
        set +o allexport
        info "Loaded environment variables from .env"
    fi
    
    local backup_success=true
    local error_messages=()
    
    # Perform backups
    if ! backup_geth_snapshot; then
        backup_success=false
        error_messages+=("Geth snapshot backup failed")
    fi
    
    if ! backup_configs; then
        backup_success=false
        error_messages+=("Configuration backup failed")
    fi
    
    backup_monitoring
    
    # Clean up old backups
    cleanup_old_backups
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$backup_success" = true ]; then
        log "Backup process completed successfully in ${duration}s"
        exit 0
    else
        error "Backup process completed with errors in ${duration}s"
        error "Failed components: ${error_messages[*]}"
        exit 1
    fi
}

# Handle script arguments
case "${1:-full}" in
    "geth")
        backup_geth_snapshot
        ;;
    "configs")
        backup_configs
        ;;
    "monitoring")
        backup_monitoring
        ;;
    "cleanup")
        cleanup_old_backups
        ;;
    "full"|*)
        main
        ;;
esac