@echo off
REM ============================================
REM BACKUP & DISASTER RECOVERY SCRIPT FOR WINDOWS
REM Untuk SEMUA Project di C:\laragon\www
REM ============================================

setlocal enabledelayedexpansion

set BACKUP_DIR=C:\backups
set DATE=%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set RETENTION_DAYS=30

echo ========================================
echo Multi-Project Backup System
echo ========================================
echo Backup Date: %DATE%
echo.

REM Create backup directory
if not exist "%BACKUP_DIR%\mysql" mkdir "%BACKUP_DIR%\mysql"
if not exist "%BACKUP_DIR%\postgres" mkdir "%BACKUP_DIR%\postgres"
if not exist "%BACKUP_DIR%\mongodb" mkdir "%BACKUP_DIR%\mongodb"
if not exist "%BACKUP_DIR%\redis" mkdir "%BACKUP_DIR%\redis"
if not exist "%BACKUP_DIR%\application" mkdir "%BACKUP_DIR%\application"
if not exist "%BACKUP_DIR%\kubernetes" mkdir "%BACKUP_DIR%\kubernetes"

REM ============================================
REM DATABASE BACKUPS
REM ============================================

echo [1/8] Backing up MySQL databases...
docker exec mysql-cluster mysqldump -u root -prootpassword --all-databases > "%BACKUP_DIR%\mysql\mysql_backup_%DATE%.sql"
if %errorlevel% equ 0 (
    echo [OK] MySQL backup completed
) else (
    echo [FAIL] MySQL backup failed
)

echo [2/8] Backing up PostgreSQL databases...
docker exec postgres-cluster pg_dump -U postgres -d multi_db > "%BACKUP_DIR%\postgres\postgres_backup_%DATE%.sql"
if %errorlevel% equ 0 (
    echo [OK] PostgreSQL backup completed
) else (
    echo [FAIL] PostgreSQL backup failed
)

echo [3/8] Backing up MongoDB databases...
docker exec mongodb-cluster mongodump --uri="mongodb://admin:mongopassword@localhost:27017" --out="/tmp/mongodb_backup"
docker cp mongodb-cluster:/tmp/mongodb_backup "%BACKUP_DIR%\mongodb\mongodb_backup_%DATE%"
if %errorlevel% equ 0 (
    echo [OK] MongoDB backup completed
) else (
    echo [FAIL] MongoDB backup failed
)

echo [4/8] Backing up Redis data...
docker exec redis-cluster redis-cli --rdb /tmp/redis_backup.rdb
docker cp redis-cluster:/tmp/redis_backup.rdb "%BACKUP_DIR%\redis\redis_backup_%DATE%.rdb"
if %errorlevel% equ 0 (
    echo [OK] Redis backup completed
) else (
    echo [FAIL] Redis backup failed
)

REM ============================================
REM APPLICATION BACKUPS
REM ============================================

echo [5/8] Backing up Laravel applications...
tar -czf "%BACKUP_DIR%\application\laravel-modernized_%DATE%.tar.gz" laravel-modernized --exclude='laravel-modernized\node_modules' --exclude='laravel-modernized\vendor'
tar -czf "%BACKUP_DIR%\application\hris-itk-ijk_%DATE%.tar.gz" HRIS-ITK-IJK --exclude='HRIS-ITK-IJK\node_modules' --exclude='HRIS-ITK-IJK\vendor'
echo [OK] Laravel applications backup completed

echo [6/8] Backing up ML models and data...
tar -czf "%BACKUP_DIR%\application\ml-models_%DATE%.tar.gz" ml-models
tar -czf "%BACKUP_DIR%\application\ml-data_%DATE%.tar.gz" ml-data
echo [OK] ML models and data backup completed

echo [7/8] Backing up environment configurations...
tar -czf "%BACKUP_DIR%\application\env-configs_%DATE%.tar.gz" .env nginx k8s
echo [OK] Environment configurations backup completed

REM ============================================
REM KUBERNETES BACKUPS
REM ============================================

echo [8/8] Backing up Kubernetes resources...
kubectl get all -n multi-project -o yaml > "%BACKUP_DIR%\kubernetes\k8s-resources_%DATE%.yaml"
kubectl get configmaps -n multi-project -o yaml > "%BACKUP_DIR%\kubernetes\k8s-configmaps_%DATE%.yaml"
kubectl get secrets -n multi-project -o yaml > "%BACKUP_DIR%\kubernetes\k8s-secrets_%DATE%.yaml"
echo [OK] Kubernetes resources backup completed

REM ============================================
REM COMPRESSION
REM ============================================

echo.
echo Compressing backups...
tar -czf "%BACKUP_DIR%\full_backup_%DATE%.tar.gz" "%BACKUP_DIR%\mysql" "%BACKUP_DIR%\postgres" "%BACKUP_DIR%\mongodb" "%BACKUP_DIR%\redis" "%BACKUP_DIR%\application" "%BACKUP_DIR%\kubernetes"

REM ============================================
REM CLEANUP OLD BACKUPS
REM ============================================

echo Cleaning up old backups (older than %RETENTION_DAYS% days)...
forfiles /p "%BACKUP_DIR%\mysql" /m mysql_backup_*.sql /d -%RETENTION_DAYS% /c "cmd /c del @path"
forfiles /p "%BACKUP_DIR%\postgres" /m postgres_backup_*.sql /d -%RETENTION_DAYS% /c "cmd /c del @path"
forfiles /p "%BACKUP_DIR%" /m full_backup_*.tar.gz /d -%RETENTION_DAYS% /c "cmd /c del @path"
echo [OK] Old backups cleaned up

REM ============================================
REM SUMMARY
REM ============================================

echo.
echo ========================================
echo Backup Summary
echo ========================================
echo Backup Date: %DATE%
echo Backup Location: %BACKUP_DIR%
echo.

echo Backup completed successfully!
pause
