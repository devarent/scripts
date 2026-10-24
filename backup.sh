#!/bin/bash

# ============================================
# BACKUP & DISASTER RECOVERY SCRIPT
# Untuk SEMUA Project di C:\laragon\www
# ============================================

set -e

BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "Multi-Project Backup System"
echo "========================================"
echo "Backup Date: $DATE"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR/mysql"
mkdir -p "$BACKUP_DIR/postgres"
mkdir -p "$BACKUP_DIR/mongodb"
mkdir -p "$BACKUP_DIR/redis"
mkdir -p "$BACKUP_DIR/application"
mkdir -p "$BACKUP_DIR/kubernetes"

# ============================================
# DATABASE BACKUPS
# ============================================

echo -e "${YELLOW}[1/8]${NC} Backing up MySQL databases..."
docker exec mysql-cluster mysqldump -u root -p${MYSQL_ROOT_PASSWORD:-rootpassword} --all-databases > "$BACKUP_DIR/mysql/mysql_backup_$DATE.sql"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} MySQL backup completed"
else
    echo -e "${RED}✗${NC} MySQL backup failed"
fi

echo -e "${YELLOW}[2/8]${NC} Backing up PostgreSQL databases..."
docker exec postgres-cluster pg_dump -U postgres -d multi_db > "$BACKUP_DIR/postgres/postgres_backup_$DATE.sql"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} PostgreSQL backup completed"
else
    echo -e "${RED}✗${NC} PostgreSQL backup failed"
fi

echo -e "${YELLOW}[3/8]${NC} Backing up MongoDB databases..."
docker exec mongodb-cluster mongodump --uri="mongodb://admin:${MONGO_PASSWORD:-mongopassword}@localhost:27017" --out="/tmp/mongodb_backup"
docker cp mongodb-cluster:/tmp/mongodb_backup "$BACKUP_DIR/mongodb/mongodb_backup_$DATE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} MongoDB backup completed"
else
    echo -e "${RED}✗${NC} MongoDB backup failed"
fi

echo -e "${YELLOW}[4/8]${NC} Backing up Redis data..."
docker exec redis-cluster redis-cli --rdb /tmp/redis_backup.rdb
docker cp redis-cluster:/tmp/redis_backup.rdb "$BACKUP_DIR/redis/redis_backup_$DATE.rdb"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Redis backup completed"
else
    echo -e "${RED}✗${NC} Redis backup failed"
fi

# ============================================
# APPLICATION BACKUPS
# ============================================

echo -e "${YELLOW}[5/8]${NC} Backing up Laravel applications..."
tar -czf "$BACKUP_DIR/application/laravel-modernized_$DATE.tar.gz" laravel-modernized --exclude='laravel-modernized/node_modules' --exclude='laravel-modernized/vendor'
tar -czf "$BACKUP_DIR/application/hris-itk-ijk_$DATE.tar.gz" HRIS-ITK-IJK --exclude='HRIS-ITK-IJK/node_modules' --exclude='HRIS-ITK-IJK/vendor'
echo -e "${GREEN}✓${NC} Laravel applications backup completed"

echo -e "${YELLOW}[6/8]${NC} Backing up ML models and data..."
tar -czf "$BACKUP_DIR/application/ml-models_$DATE.tar.gz" ml-models
tar -czf "$BACKUP_DIR/application/ml-data_$DATE.tar.gz" ml-data
echo -e "${GREEN}✓${NC} ML models and data backup completed"

echo -e "${YELLOW}[7/8]${NC} Backing up environment configurations..."
tar -czf "$BACKUP_DIR/application/env-configs_$DATE.tar.gz" .env nginx k8s
echo -e "${GREEN}✓${NC} Environment configurations backup completed"

# ============================================
# KUBERNETES BACKUPS
# ============================================

echo -e "${YELLOW}[8/8]${NC} Backing up Kubernetes resources..."
kubectl get all -n multi-project -o yaml > "$BACKUP_DIR/kubernetes/k8s-resources_$DATE.yaml"
kubectl get configmaps -n multi-project -o yaml > "$BACKUP_DIR/kubernetes/k8s-configmaps_$DATE.yaml"
kubectl get secrets -n multi-project -o yaml > "$BACKUP_DIR/kubernetes/k8s-secrets_$DATE.yaml"
echo -e "${GREEN}✓${NC} Kubernetes resources backup completed"

# ============================================
# COMPRESSION & ENCRYPTION
# ============================================

echo ""
echo -e "${YELLOW}Compressing backups...${NC}"
tar -czf "$BACKUP_DIR/full_backup_$DATE.tar.gz" "$BACKUP_DIR/mysql" "$BACKUP_DIR/postgres" "$BACKUP_DIR/mongodb" "$BACKUP_DIR/redis" "$BACKUP_DIR/application" "$BACKUP_DIR/kubernetes"

echo -e "${YELLOW}Encrypting backup...${NC}"
if [ -n "$ENCRYPTION_KEY" ]; then
    openssl enc -aes-256-cbc -salt -in "$BACKUP_DIR/full_backup_$DATE.tar.gz" -out "$BACKUP_DIR/full_backup_$DATE.tar.gz.enc" -k "$ENCRYPTION_KEY"
    rm "$BACKUP_DIR/full_backup_$DATE.tar.gz"
    echo -e "${GREEN}✓${NC} Backup encrypted"
else
    echo -e "${YELLOW}⚠${NC} No encryption key provided, backup not encrypted"
fi

# ============================================
# UPLOAD TO CLOUD STORAGE
# ============================================

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${YELLOW}Uploading to AWS S3...${NC}"
    if [ -f "$BACKUP_DIR/full_backup_$DATE.tar.gz.enc" ]; then
        aws s3 cp "$BACKUP_DIR/full_backup_$DATE.tar.gz.enc" "s3://${AWS_BUCKET:-multi-project-backups}/full_backup_$DATE.tar.gz.enc"
    else
        aws s3 cp "$BACKUP_DIR/full_backup_$DATE.tar.gz" "s3://${AWS_BUCKET:-multi-project-backups}/full_backup_$DATE.tar.gz"
    fi
    echo -e "${GREEN}✓${NC} Backup uploaded to S3"
else
    echo -e "${YELLOW}⚠${NC} AWS credentials not configured, skipping S3 upload"
fi

# ============================================
# CLEANUP OLD BACKUPS
# ============================================

echo -e "${YELLOW}Cleaning up old backups (older than $RETENTION_DAYS days)...${NC}"
find "$BACKUP_DIR" -name "mysql_backup_*.sql" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "postgres_backup_*.sql" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "full_backup_*.tar.gz*" -mtime +$RETENTION_DAYS -delete
echo -e "${GREEN}✓${NC} Old backups cleaned up"

# ============================================
# SUMMARY
# ============================================

echo ""
echo "========================================"
echo "Backup Summary"
echo "========================================"
echo "Backup Date: $DATE"
echo "Backup Location: $BACKUP_DIR"
echo "Total Size: $(du -sh $BACKUP_DIR | cut -f1)"
echo "Retention: $RETENTION_DAYS days"
echo ""

# Send notification
if [ -n "$SLACK_WEBHOOK" ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"Multi-Project Backup Completed\nDate: $DATE\nSize: $(du -sh $BACKUP_DIR | cut -f1)\"}" \
        "$SLACK_WEBHOOK"
fi

echo -e "${GREEN}Backup completed successfully!${NC}"
