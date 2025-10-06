# Local Deployment Guide

This guide walks you through deploying the TxEventQ serverless application locally for development and testing.

## Prerequisites

Ensure you have the following installed:

- Java 23
- Gradle
- Fn CLI
- Podman (with machine initialized and running)
- SQLcl (sql command)

## Step 1: Start Local Containers

### 1.1 Start Oracle Database FREE

```bash
podman run -d --name oradbtx \
  -p 1521:1521 \
  -e ORACLE_PWD=YourPassword123 \
  container-registry.oracle.com/database/free:latest

# Wait for database to be ready (~2-3 minutes)
podman logs -f oradbtx 2>&1 | grep -m 1 'DATABASE IS READY TO USE!'
```

### 1.2 Start Mailpit SMTP Server

```bash
podman run -d --name mailpit \
  -p 1025:1025 \
  -p 8025:8025 \
  axllent/mailpit:latest

# Access UI at http://localhost:8025
```

## Step 2: Setup Database

### 2.1 Create Database Objects

Create the necessary database scripts in the `db/` directory:

**`db/01_grant_permissions.sql`**:

```sql
-- Grant permissions to PDBADMIN for Advanced Queuing
GRANT EXECUTE ON DBMS_AQADM TO PDBADMIN;
GRANT AQ_ADMINISTRATOR_ROLE TO PDBADMIN;

EXIT;
```

**`db/02_create_queue.sql`**:

```sql
-- Drop existing queue (if exists)
BEGIN
    DBMS_AQADM.STOP_QUEUE(queue_name => 'REPORT_QUEUE');
    DBMS_AQADM.DROP_QUEUE(queue_name => 'REPORT_QUEUE');
    DBMS_AQADM.DROP_QUEUE_TABLE(queue_table => 'REPORT_QUEUE_TABLE');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- Create TxEventQ queue
BEGIN
    DBMS_AQADM.CREATE_TRANSACTIONAL_EVENT_QUEUE(
        queue_name => 'REPORT_QUEUE',
        queue_payload_type => 'JSON',
        multiple_consumers => FALSE,
        storage_clause => NULL,
        comment => 'Queue for report generation requests'
    );
END;
/

-- Start queue
BEGIN
    DBMS_AQADM.START_QUEUE(queue_name => 'REPORT_QUEUE');
END;
/

-- Set retention time (7 days)
BEGIN
    DBMS_AQADM.SET_QUEUE_TABLE_PROPERTY(
        queue_table => 'REPORT_QUEUE_TABLE',
        property => 'RETENTION_TIME',
        value => '604800'
    );
END;
/

-- Verify queue
SELECT queue_name, queue_type, enqueue_enabled, dequeue_enabled
FROM USER_QUEUES
WHERE queue_name = 'REPORT_QUEUE';
```

**`db/03_enqueue_test_messages.sql`**:

```sql
-- Enqueue test messages
DECLARE
    enqueue_options    DBMS_AQ.ENQUEUE_OPTIONS_T;
    message_properties DBMS_AQ.MESSAGE_PROPERTIES_T;
    message_handle     RAW(16);
    message            JSON;
BEGIN
    -- Message 1
    message := JSON('{"title": "Monthly Sales Report", "content": "Sales data for January 2025...", "date": "2025-01-15T10:30:00Z"}');

    DBMS_AQ.ENQUEUE(
        queue_name         => 'REPORT_QUEUE',
        enqueue_options    => enqueue_options,
        message_properties => message_properties,
        payload            => message,
        msgid              => message_handle
    );

    -- Message 2
    message := JSON('{"title": "Quarterly Financial Summary", "content": "Q4 2024 financial summary...", "date": "2025-01-20T14:00:00Z"}');

    DBMS_AQ.ENQUEUE(
        queue_name         => 'REPORT_QUEUE',
        enqueue_options    => enqueue_options,
        message_properties => message_properties,
        payload            => message,
        msgid              => message_handle
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Enqueued 2 test messages');
END;
/
```

### 2.2 Execute Database Scripts

```bash
# Grant permissions to PDBADMIN (connect as SYS)
sql sys/YourPassword123@//localhost:1521/FREEPDB1 as sysdba @db/01_grant_permissions.sql

# Create queue (connect as PDBADMIN)
sql pdbadmin/YourPassword123@//localhost:1521/FREEPDB1 @db/02_create_queue.sql

# Enqueue test messages
sql pdbadmin/YourPassword123@//localhost:1521/FREEPDB1 @db/03_enqueue_test_messages.sql
```

## Step 3: Build and Deploy Function

### 3.1 Start Fn Server

```bash
fn start -d
```

### 3.2 Build and Deploy

```bash
cd function
fn deploy --app txeventq-local --local
```

### 3.3 Configure Function

```bash
fn config app txeventq-local ENVIRONMENT DEVELOPMENT
fn config app txeventq-local QUEUE_NAME REPORT_QUEUE
fn config app txeventq-local BATCH_SIZE 5
fn config app txeventq-local SMTP_HOST localhost
fn config app txeventq-local SMTP_PORT 1025
fn config app txeventq-local SMTP_USERNAME test
fn config app txeventq-local SMTP_PASSWORD test
fn config app txeventq-local SENDER_EMAIL noreply@example.com
fn config app txeventq-local RECIPIENT_EMAILS user@example.com
fn config app txeventq-local LOCAL_TEMP_DIR /tmp/reports
fn config app txeventq-local DB_CONNECTION_STRING "jdbc:oracle:thin:@localhost:1521/FREEPDB1"
fn config app txeventq-local DB_USERNAME pdbadmin
fn config app txeventq-local DB_PASSWORD "YourPassword123"
```

## Step 4: Test the Function

### 4.1 Invoke Function

```bash
echo '{}' | fn invoke txeventq-local txeventq-processor
```

Expected output:

```
Processed 2 messages
```

### 4.2 Verify Results

**Check generated files**:

```bash
ls /tmp/reports/
```

You should see two files:

- `Monthly_Sales_Report_<hash>.txt`
- `Quarterly_Financial_Summary_<hash>.txt`

**Check emails**:
Open http://localhost:8025 in your browser to see the sent emails.

**Check database queue**:

```bash
sql pdbadmin/YourPassword123@//localhost:1521/FREEPDB1 @db/04_check_queue_status.sql
```

## Step 5: Enqueue More Messages (Optional)

To test the function with additional messages:

```bash
sql pdbadmin/YourPassword123@//localhost:1521/FREEPDB1 @db/03_enqueue_test_messages.sql
echo '{}' | fn invoke txeventq-local txeventq-processor
```

## Troubleshooting

### Database not ready

If you get connection errors, wait longer for the database to initialize:

```bash
podman logs -f oradbtx
```

### Function build errors

Ensure Java 23 and Gradle are properly installed:

```bash
java -version
gradle -version
```

### Fn server not running

Check if Fn server is running:

```bash
fn version
```

### Emails not appearing

Check Mailpit logs:

```bash
podman logs mailpit
```

## Cleanup

To stop and remove all containers:

```bash
# Stop containers
podman stop oradbtx mailpit
fn stop

# Remove containers
podman rm oradbtx mailpit

# Remove generated files
rm -rf /tmp/reports/*
```

## Next Steps

Once you've tested locally and are ready to deploy to OCI:

→ **[CLOUD.md](CLOUD.md)** - Cloud deployment guide
