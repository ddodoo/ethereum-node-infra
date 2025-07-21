#!/bin/bash

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
GETH_DATA_DIR="${GETH_DATA_DIR:-$PROJECT_ROOT/data/geth}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to check if Geth is running
check_geth_status() {
    local container_name="ethereum-geth"
    if docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        return 0
    else
        return 1
    fi
}

# Function to create Geth snapshot backup
backup_geth_snapshot() {
    log "Starting Geth snapshot backup..."
    
    if check_geth_status; then
        log "Geth is running. Creating online backup..."
        
        # Create backup using Geth's export functionality
        local backup_file="$BACKUP_DIR/geth_snapshot_${TIMESTAMP}.tar.gz"
        
        # Stop writing to database temporarily and create consistent snapshot
        docker exec ethereum-geth geth attach --exec "debug.setBlockProfileRate(0)"
        
        # Create compressed backup
        if tar -czf "$backup_file" -C "$(dirname "$GETH_DATA_DIR")" "$(basename "$GETH_DATA_DIR")"; then
            log "Geth snapshot backup created: $backup_file"
            
            # Resume normal operations
            docker exec ethereum-geth geth attach --exec "debug.setBlockProfileRate(1)"
            
            # Verify backup integrity
            if tar -tzf "$backup_file" >/dev/null 2>&1; then
                log "Backup integrity verified"
                local backup_size=$(du -h "$backup_file" | cut -f1)
                log "Backup size: $backup_size"
            else
                error "Backup integrity check failed"
                return 1
            fi
        else
            error "Failed to create Geth snapshot backup"
            return 1
        fi
    else
        warn "Geth is not running. Creating offline backup..."
        
        if [ -d "$GETH_DATA_DIR" ]; then
            local backup_file="$BACKUP_DIR/geth_offline_${TIMESTAMP}.tar.gz"
            if tar -czf "$backup_file" -C "$(dirname "$GETH_DATA_DIR")" "$(basename "$GETH_DATA_DIR")"; then
                log "Offline Geth backup created: $backup_file"
            else
                error "Failed to create offline Geth backup"
                return 1
            fi
        else
            warn "Geth data directory not found: $GETH_DATA_DIR"
            return 1
        fi
    fi
}

# Function to backup configuration files
backup_configs() {
    log "Backing up configuration files..."
    
    local config_backup="$BACKUP_DIR/configs_${TIMESTAMP}.tar.gz"
    
    if tar -czf "$config_backup" -C "$PROJECT_ROOT" configs docker-compose.yml docker-compose.prod.yml .env; then
        log "Configuration backup created: $config_backup"
    else
        error "Failed to create configuration backup"
        return 1
    fi
}

# Function to backup monitoring data
backup_monitoring() {
    log "Backing up monitoring data..."
    
    # Backup Prometheus data
    if docker ps --format "table {{.Names}}" | grep -q "prometheus"; then
        local prometheus_backup="$BACKUP_DIR/prometheus_${TIMESTAMP}.tar.gz"
        docker exec prometheus tar -czf - /prometheus 2>/dev/null | cat > "$prometheus_backup" || true
        if [ -s "$prometheus_backup" ]; then
            log "Prometheus data backup created: $prometheus_backup"
        else
            warn "Prometheus backup is empty or failed"
            rm -f "$prometheus_backup"
        fi
    fi
    
    # Backup Grafana data
    if docker ps --format "table {{.Names}}" | grep -q "grafana"; then
        local grafana_backup="$BACKUP_DIR/grafana_${TIMESTAMP}.tar.gz"
        docker exec grafana tar -czf - /var/lib/grafana 2>/dev/null | cat > "$grafana_backup" || true
        if [ -s "$grafana_backup" ]; then
            log "Grafana data backup created: $grafana_backup"
        else
            warn "Grafana backup is empty or failed"
            rm -f "$grafana_backup"
        fi
    fi
}

# Function to clean up old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete
        local remaining_count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f | wc -l)
        log "Backup cleanup completed. Remaining backups: $remaining_count"
    fi
}


# Main backup function
main() {
    local start_time=$(date +%s)
    
    log "Starting backup process..."
    
    # Load environment variables if .env file exists
    if [ -f "$PROJECT_ROOT/.env" ]; then
        set -o allexport
        source "$PROJECT_ROOT/.env"
        set +o allexport
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
    
    backup_monitoring || true  # Non-critical, continue on failure
    
    # Upload to cloud storage if configured
    upload_to_cloud || true
    
    # Clean up old backups
    cleanup_old_backups
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$backup_success" = true ]; then
        log "Backup process completed successfully in ${duration}s"
        send_notification "success" "Ethereum node backup completed successfully in ${duration}s"
    else
        error "Backup process completed with errors in ${duration}s"
        error "Failed components: ${error_messages[*]}"
        send_notification "error" "Backup process failed: ${error_messages[*]}"
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