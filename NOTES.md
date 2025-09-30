# Notes about requirements and design

The main objective is that messages can be queued in Oracle Database TxEventQ, and a OCI Serverless Function can unqueue messages, put the content in Object Storage, create a Pre-Authenticated Request link and send it as part of an email (with template). The execution of the function needs to happen periodically.

This project is using Oracle Autonomous Database 23ai and Oracle Cloud Infrastructure as a Proof of Concept.

## Infrastructure Requirements

- Object Storage Bucket (created via Terraform, name passed as variable)
- Oracle Autonomous Database 23ai (public endpoint, mTLS connection with wallet files, created via Terraform)
- IAM permissions to serverless function to put objects in Object Storage and create PAR (created via Terraform)
- OCI Serverless Application (created via Terraform)
- OCI Monitoring Alarm (triggers every 5 minutes unconditionally) (created via Terraform)
- OCI Notification Topic (created via Terraform)
- Compute Instance (created via Terraform) for fake SMTP (axllent/mailpit) server running as a podman container
  - In Public subnet with public IP address
  - Network Security Group to open SMTP port

## Design

### Local Development Environment (Implemented First)

For local development, the following components will run on the developer machine:

- **Oracle Database**: `container-registry.oracle.com/database/free:latest` (Oracle Database FREE 23ai) running in a podman container
  - Port: 1521
  - No wallet required (username/password authentication)
  - Database: FREEPDB1 (pluggable database)
- **SMTP Server**: `axllent/mailpit:latest` running in a podman container
  - SMTP Port: 1025
  - UI Port: 8025
- **Function Runtime**: Fn Project local server (`fn start`)
- **File Storage**: Files stored in a temporary local directory instead of Object Storage
- **No PAR**: Since files are local, no Pre-Authenticated Request links will be generated in local mode

**Prerequisites (assumed installed)**:
- Java 23
- Gradle
- Fn CLI
- Podman

The local function will:
1. Connect to local Oracle Database FREE container
2. Process TxEventQ messages
3. Save files to local temporary directory
4. Send emails via local mailpit with file path (instead of PAR link)

**Local invocation**: Use `fn invoke` command

### OCI Production Environment

In order to simulate the SMTP server we are using `axllent/mailpit` running on a compute instance in OCI. The compute is in a Public subnet with a public IP address. We need a Network Security Group to open the port for the SMTP server.

`axllent/mailpit` should implement basic authentication for UI and SMTP AUTH (plain).

Provisioning of SMTP server happens with Ansible playbook.

The serverless function scheduling is handled by OCI Resource Scheduler with an Alarm that triggers your function.

The OCI Monitoring Alarm will call every 5 minutes the serverless function through OCI Resource Scheduler by using a notification topic.

## Serverless Function Tasks

Fn Serverless Function in Java 23 (Gradle build).

**Function Configuration Parameters** (configured at function/application level):
- `QUEUE_NAME`: TxEventQ queue name
- `BATCH_SIZE`: Max messages to process per invocation
- `PAR_VALIDITY_DAYS`: PAR link validity period (OCI only)
- `SMTP_HOST`: SMTP server hostname
- `SMTP_PORT`: SMTP server port
- `SMTP_USERNAME`: SMTP authentication username
- `SMTP_PASSWORD`: SMTP authentication password
- `SENDER_EMAIL`: Email sender address
- `RECIPIENT_EMAILS`: Comma-separated list of recipient emails
- `LOCAL_TEMP_DIR`: Local temporary directory path (local mode only)
- `BUCKET_NAME`: Object Storage bucket name (OCI mode only)
- `DB_CONNECTION_STRING`: Database connection string
- `DB_USERNAME`: Database username
- `DB_PASSWORD`: Database password

**Dependencies** (use latest versions):
- Oracle JDBC driver
- Oracle AQ libraries
- OCI SDK (for Object Storage and PAR - OCI mode only)
- JavaMail

**OCI Wallet Handling** (OCI mode only):
- Follow best practices for wallet packaging with function
- Wallet location: follow best practices

### Database Connection

**Local mode**:
- Connect to Oracle Database FREE container (FREEPDB1)
- Username/password authentication (no wallet)
- Port: 1521

**OCI mode**:
- Connect to Autonomous Database using mTLS (wallet files)
- Serverless function can reach database directly on public endpoint

### TxEventQ Processing

- Queue name: configured via Terraform variable (function config)
- Single consumer queue
- Message format: JSON with structure: `{title, content, date}` where `date` is ISO8601 format
- Payload type: JSON
- Retention policy: 7 days (time-based)
- Batch size: configurable per function variable (max messages to process per invocation)
- Error handling: log errors if processing fails
- Messages are deleted after successful processing
- Queue creation: SQL scripts in FREEPDB1 schema
- User permissions: To be determined during implementation (attempt dequeue and add necessary grants)

### Function Workflow

1. Check for TxEventQ messages in the queue
2. Unqueue messages (up to batch size limit)
3. If queue is empty, return gracefully
4. For each message:
   - Extract `title`, `content`, and `date` (ISO8601) from JSON
   - Sanitize `title` to remove special characters (`/`, `\`, etc.)
   - Create txt file with content
   - File naming: `{sanitized_title}_{datetime}.txt` (datetime includes timestamp to avoid duplicates)
   - **Local mode**: Save to local temporary directory, include file path in email
   - **OCI mode**: PUT the txt file into Object Storage
   - **OCI mode**: Create Pre-Authenticated Request (PAR) link
     - Read-only access
     - Validity period: configurable (in days)
   - Send email using template with download link (PAR in OCI, file path locally)

### Email Configuration

- SMTP server: mailpit with Plain Auth
- SMTP credentials: configured at function/application level (function config for POC, not OCI Vault)
- Sender email: configured at function/application level
- Recipients: configured at function/application level
- Template: simple introduction + download link (easy to modify)

## Database Setup

**SQL Scripts** (to be created):
- Queue creation in FREEPDB1 schema
- Test message enqueue script with sample JSON payloads
- Required database objects

**Example test message**:
```json
{
  "title": "Test Document",
  "content": "This is the content of the test document",
  "date": "2025-09-30T10:30:00Z"
}
```

## OCI Deployment (Terraform)

**IAM Configuration**:
- Dynamic Group with matching rule for serverless functions
- IAM Policy statements for Object Storage PUT and PAR creation

**Deployment workflow**:
1. Build function with Gradle
2. Push to OCIR
3. Deploy via Terraform with function configuration variables

## Implementation Tracks

**Local Development** (podman + Fn Server):
- Oracle Database FREE container
- mailpit container
- Local file storage
- Development and testing

**OCI Deployment** (Ansible + Terraform):
- Autonomous Database
- mailpit on compute instance (Ansible provisioning)
- Object Storage + PAR
- Production-like environment
