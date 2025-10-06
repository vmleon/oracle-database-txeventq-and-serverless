# Database Scripts

## Local (Oracle DB FREE)

```bash
sql sys/YourPassword123@//localhost:1521/FREEPDB1 as sysdba @01_grant_permissions.sql
sql pdbadmin/YourPassword123@//localhost:1521/FREEPDB1 @02_create_queue.sql
sql pdbadmin/YourPassword123@//localhost:1521/FREEPDB1 @03_enqueue_test_messages.sql
```

## Cloud (Autonomous Database)

```bash
sql ADMIN/YourPassword@connection_string @02_create_queue.sql
sql ADMIN/YourPassword@connection_string @03_enqueue_test_messages.sql
```

## Scripts

- `01_grant_permissions.sql` - Grants AQ permissions to PDBADMIN
- `02_create_queue.sql` - Creates TxEventQ queue with JSON payload
- `03_enqueue_test_messages.sql` - Enqueues 2 test messages
- `04_check_queue_status.sql` - Checks queue status
