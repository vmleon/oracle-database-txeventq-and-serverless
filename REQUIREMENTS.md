# Requirements

## Objective

Messages can be queued in Oracle Database TxEventQ, and an OCI Serverless Function can unqueue messages, put the content in Object Storage, create a Pre-Authenticated Request link and send it as part of an email (with template). The execution of the function needs to happen periodically.

This project is using Oracle Autonomous Database 23ai and Oracle Cloud Infrastructure as a Proof of Concept.

## Functional Requirements

### Message Processing
- Dequeue messages from TxEventQ queue in Oracle Database
- Process messages in batches (configurable batch size)
- Extract message payload: `{title, content, date}` where `date` is ISO8601 format
- Gracefully handle empty queue (NO_WAIT mode)

### File Management
- Generate unique filenames using: `{sanitized_title}_{content_hash}.txt`
- Sanitize title to remove special characters (`/`, `\`, etc.)
- Create content hash (SHA-256, first 8 characters) for deduplication
- **Local mode**: Save files to local temporary directory
- **OCI mode**: Upload files to Object Storage bucket

### Pre-Authenticated Request (PAR)
- Create read-only PAR links for uploaded objects (OCI mode only)
- Configurable validity period (in days)
- PAR links included in email notifications

### Email Notifications
- Send HTML-formatted emails with report details
- Email template with placeholders: `{DATE}`, `{TITLE}`, `{DOWNLOAD_LINK}`
- Subject: "Data Safe Report"
- Support multiple recipients (comma-separated)
- Authenticate with SMTP server (Plain Auth)

### Periodic Execution
- Function triggered every 5 minutes
- Trigger mechanism: OCI Monitoring Alarm → Notification Topic → Function Invocation
- Ability to pause processing (disable alarm or set concurrency to 0)

## Non-Functional Requirements

### Performance
- Function timeout: 3 minutes (180 seconds)
- Visibility timeout: 4 minutes (prevents message re-processing during function execution)
- Process batch within timeout constraint
- Default batch size: 5 messages (tunable)

### Reliability
- Transaction boundary: dequeue → create file → send email → commit (all-or-nothing)
- Messages deleted after successful processing (commit)
- Failed messages remain in queue for retry
- Continue processing remaining messages if one fails (optimistic processing)

### Security
- mTLS authentication for Autonomous Database (wallet-based)
- Resource Principal authentication for OCI services (no API keys)
- Secrets stored in function configuration (POC) or OCI Vault (production)
- Object Storage: private bucket, PAR links only

### Observability
- Log processed message metadata to function logs
- Structured logging for better searchability
- Function metrics tracked in OCI Monitoring
- Optional: audit trail in database table

### Cost
- Target monthly cost for POC: ~$25-30/month
- Use Always Free tier resources where possible
- Optimize resource allocation (minimal OCPU, memory)

## Message Format

### Queue Message Schema
```json
{
  "title": "Monthly Sales Report",
  "content": "Sales data for January 2025...",
  "date": "2025-01-15T10:30:00Z"
}
```

### Email Template Structure
```html
<html>
<body>
<h2>Data Safe Report</h2>
<p>Date: {DATE}</p>
<p>A new report is available for download:</p>
<p><a href="{DOWNLOAD_LINK}">Download {TITLE}</a></p>
</body>
</html>
```

## Configuration Parameters

Function configuration variables:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `ENVIRONMENT` | Execution mode | `DEVELOPMENT` or `PRODUCTION` |
| `QUEUE_NAME` | TxEventQ queue name | `REPORT_QUEUE` |
| `BATCH_SIZE` | Max messages per invocation | `5` |
| `PAR_VALIDITY_DAYS` | PAR link validity period | `7` |
| `SMTP_HOST` | SMTP server hostname | `mailpit.example.com` |
| `SMTP_PORT` | SMTP server port | `1025` |
| `SMTP_USERNAME` | SMTP authentication username | `user@example.com` |
| `SMTP_PASSWORD` | SMTP authentication password | `secret` |
| `SENDER_EMAIL` | Email sender address | `noreply@example.com` |
| `RECIPIENT_EMAILS` | Comma-separated recipients | `user1@example.com,user2@example.com` |
| `LOCAL_TEMP_DIR` | Local temp directory (dev only) | `/tmp/reports` |
| `BUCKET_NAME` | Object Storage bucket (OCI only) | `reports-bucket` |
| `DB_CONNECTION_STRING` | Database connection string | `jdbc:oracle:thin:@...` |
| `DB_USERNAME` | Database username | `txeventq_user` |
| `DB_PASSWORD` | Database password | `YourPassword123#` |
| `WALLET_BASE64` | Base64-encoded wallet zip (OCI only) | `UEsDBBQA...` |
| `WALLET_PASSWORD` | Wallet password (OCI only) | `WalletPassword123#` |
| `FUNCTION_TIMEOUT` | Function timeout in seconds | `180` |
| `DEQUEUE_WAIT_TIME` | Dequeue wait time in seconds | `0` (NO_WAIT) |

## Success Criteria

### Local Development
- Function successfully processes messages from local Oracle DB FREE container
- Files saved to local directory with correct naming convention
- Emails sent via local mailpit with proper template rendering
- All test messages processed without errors

### OCI Production
- Infrastructure deployed via Terraform without manual intervention
- Function automatically triggered every 5 minutes
- Messages processed end-to-end:
  - Dequeued from Autonomous Database
  - Files uploaded to Object Storage
  - PAR links generated
  - Emails sent with functional download links
- Queue emptied after processing
- Zero data loss (transaction consistency)

## Out of Scope (POC)

- User authentication/authorization for PAR links
- Message encryption at application level
- Dead Letter Queue for failed messages
- Idempotency checks (duplicate message prevention)
- Connection pooling (Oracle UCP)
- Advanced monitoring dashboards
- Auto-scaling based on queue depth
- Multi-region deployment
- Disaster recovery planning
