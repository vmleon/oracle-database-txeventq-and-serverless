# Architecture

## System Overview

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│ OCI Resource    │         │  OCI Functions   │         │ Autonomous DB   │
│   Scheduler     ├────────>│  (Serverless)    ├────────>│   23ai w/       │
│ (CRON trigger)  │         │                  │         │   TxEventQ      │
└─────────────────┘         │  - Dequeue msgs  │         └─────────────────┘
                            │  - Create files  │
                            │  - Upload to OS  │                 │
                            │  - Create PARs   │                 │
                            │  - Send emails   │                 │
                            └────────┬─────────┘                 │
                                     │                           │
                                     v                           │
                            ┌──────────────────┐                 │
                            │ Object Storage   │                 │
                            │  + PAR Links     │                 │
                            └──────────────────┘                 │
                                     │                           │
                                     v                           │
                            ┌──────────────────┐                 │
                            │  SMTP Server     │                 │
                            │  (mailpit)       │<────────────────┘
                            └──────────────────┘
                                     │
                                     v
                            ┌──────────────────┐
                            │   Email Client   │
                            └──────────────────┘
```

## Execution Modes

### Local Development Environment

**Purpose**: Development, testing, and iteration without OCI costs

**Components**:

- **Oracle Database**: `container-registry.oracle.com/database/free:latest` (Oracle Database FREE 23ai)
  - Port: 1521
  - PDB: FREEPDB1
  - Authentication: username/password (no wallet)
- **SMTP Server**: `axllent/mailpit:latest`
  - SMTP Port: 1025
  - UI Port: 8025
- **Function Runtime**: Fn Project local server (`fn start`)
- **File Storage**: Local temporary directory
- **No PAR Links**: Files referenced by local path in emails

**Invocation**: Manual via `fn invoke` command

### OCI Production Environment

**Purpose**: Production-like environment with full OCI integration

**Components**:

- **Oracle Autonomous Database 23ai Serverless**
  - Public endpoint, mTLS authentication
  - Wallet files (base64-encoded in function config)
- **OCI Functions**
  - Private subnet, Resource Principal authentication
  - Custom Java 23 image from OCIR
- **Object Storage**
  - Private bucket, PAR links for access
- **SMTP Server**: `axllent/mailpit` on compute instance
  - Public subnet with public IP
  - Provisioned via Ansible
- **Trigger**: OCI Resource Scheduler (CRON-based)

**Invocation**: Automatic via Resource Scheduler → Function (direct invocation)

## Network Architecture (OCI)

### VCN Layout

```
VCN: 10.0.0.0/16
├── Public Subnet: 10.0.1.0/24
│   ├── Internet Gateway (ingress/egress to internet)
│   └── Resources:
│       └── Compute Instance (mailpit)
│           - Public IP for SMTP/UI access
│           - NSG: Allow 1025/tcp, 8025/tcp from VCN
│
└── Private Subnet: 10.0.2.0/24
    ├── NAT Gateway (egress to internet for ADB access)
    ├── Service Gateway (optional, for Object Storage)
    └── Resources:
        └── OCI Functions
            - No public IP
            - NSG: Egress to ADB:1522, SMTP:1025, OS:443
```

### Network Security Groups (NSGs)

**Function NSG** (private subnet):

- Egress to ADB public endpoint: TCP/1522
- Egress to SMTP server: TCP/1025 (from 10.0.2.0/24 to 10.0.1.0/24)
- Egress to Object Storage: HTTPS/443 (via NAT or Service Gateway)

**Compute NSG** (public subnet):

- Ingress: TCP/1025 from VCN CIDR (SMTP)
- Ingress: TCP/8025 from 0.0.0.0/0 (UI access from internet)
- Egress: Allow all (for yum updates)

### Connectivity Paths

1. **Function → ADB**: Private subnet → NAT Gateway → Internet → ADB public endpoint (mTLS)
2. **Function → Object Storage**: Private subnet → Service Gateway (preferred) or NAT Gateway → Object Storage
3. **Function → SMTP**: Private subnet → Public subnet (10.0.1.0/24)
4. **Developer → Mailpit UI**: Internet → Public IP → Compute instance:8025

## Data Flow

### Message Processing Workflow

```
1. Resource Scheduler Triggers (CRON-based)
   └─> Function Invocation (direct, no intermediate services)

2. Function Cold Start (if container not warm)
   ├─> Extract wallet to /tmp/wallet (OCI mode)
   ├─> Set system properties for TNS_ADMIN
   └─> Initialize OCI SDK clients (Resource Principal)

3. Database Connection
   ├─> LOCAL: Direct connection (no pooling)
   └─> OCI: DRCP connection (Database Resident Connection Pooling) with Wallet (mTLS)

4. Dequeue Messages (batch)
   ├─> Set dequeue options (REMOVE, ON_COMMIT, NO_WAIT)
   ├─> Loop up to BATCH_SIZE
   │   ├─> Dequeue message
   │   └─> Parse JSON payload {title, content, date}
   └─> If queue empty, return gracefully

5. Process Each Message
   ├─> Sanitize title (remove special chars)
   ├─> Generate content hash (SHA-256, 8 chars)
   ├─> Create filename: {title}_{hash}.txt
   ├─> LOCAL: Save to temp directory
   │   └─> Email link: file:///path/to/file.txt
   └─> OCI: Upload to Object Storage
       ├─> PUT object (overwrites if exists - deduplication)
       ├─> Create PAR (read-only, configurable expiry)
       └─> Email link: https://objectstorage...

6. Send Email
   ├─> Load HTML template from resources
   ├─> Replace placeholders: {DATE}, {TITLE}, {DOWNLOAD_LINK}
   ├─> Connect to SMTP (Plain Auth)
   └─> Send to recipients

7. Commit Transaction
   └─> Messages deleted from queue

8. Return Response
   └─> "Processed N messages"
```

### Error Handling Strategy

**Optimistic Processing**:

- If one message fails, log error and continue with next
- Batch commit at end (all-or-nothing for dequeued messages)
- Failed messages remain in queue for next invocation

**Transaction Boundaries**:

```
BEGIN TRANSACTION
  ├─> Dequeue message(s)
  ├─> Process message 1 (file + email)
  ├─> Process message 2 (file + email)
  └─> COMMIT (messages deleted)
EXCEPTION
  └─> ROLLBACK (messages remain in queue)
```

**Visibility Timeout**: 4 minutes

- Messages invisible to other consumers during processing
- If function times out (3 min), messages reappear in queue after 4 min
- Prevents concurrent processing of same message

## Component Architecture

### Function Structure

```
function/
├── src/main/java/com/oracle/fn/
│   └── TxEventQProcessor.java
│       ├── @FnConfiguration configure()
│       │   ├── Read ENVIRONMENT config
│       │   ├── Extract wallet (OCI mode)
│       │   └── Initialize OCI clients
│       ├── handleRequest() [entry point]
│       ├── getConnection() [connection management]
│       ├── processMessages() [batch dequeue]
│       ├── processMessage() [single message]
│       ├── uploadToObjectStorageAndCreatePar()
│       ├── saveToLocalDirectory()
│       └── sendEmail()
├── src/main/resources/
│   └── email-template.html
├── build.gradle
└── func.yaml
```

### Database Schema

```
TxEventQ Queue: REPORT_QUEUE
├── Queue Table: REPORT_QUEUE_TABLE
│   ├── Payload Type: JSON
│   ├── Multiple Consumers: FALSE
│   ├── Retention: 7 days (604800 seconds)
│   └── Storage: Default (system-managed)
├── Dequeue Options:
│   ├── Mode: REMOVE (delete after commit)
│   ├── Visibility: ON_COMMIT
│   └── Wait Time: 0 (NO_WAIT)
└── User: PDBADMIN (local) or ADMIN (ADB)
    ├── CONNECT, RESOURCE
    ├── EXECUTE ON DBMS_AQ, DBMS_AQADM
    └── QUOTA UNLIMITED ON DATA

Connection Pooling (OCI only):
├── DRCP (Database Resident Connection Pooling)
│   ├── Pool Name: Default pool (automatically created on ADB)
│   ├── Connection String: Append :POOLED suffix
│   ├── Benefits: Reduced connection overhead for serverless functions
│   └── Configuration: No custom setup required (ADB default)

Optional Monitoring Table: PROCESSED_MESSAGES
├── id (IDENTITY)
├── message_id (RAW)
├── title (VARCHAR2)
├── processed_date (TIMESTAMP)
├── file_name (VARCHAR2)
├── status (VARCHAR2)
└── error_message (CLOB)
```

## IAM Architecture (OCI)

### Dynamic Groups

**Function Dynamic Group**:
```
Name: txeventq-function-dg
Matching Rule: ALL {
  resource.type='fnfunc',
  resource.compartment.id='<compartment-ocid>'
}
```

**Resource Scheduler Dynamic Group**:
```
Name: txeventq-scheduler-dg
Matching Rule: ALL {
  resource.type='resourceschedule',
  resource.id='<resource-schedule-ocid>'
}
```

### Policies

**Function Policy** (for Object Storage and Network access):
```hcl
# Object Storage access
allow dynamic-group txeventq-function-dg to manage objects
  in compartment <name>
  where target.bucket.name='<bucket-name>'

# PAR creation
allow dynamic-group txeventq-function-dg to manage preauthenticated-requests
  in compartment <name>
  where target.bucket.name='<bucket-name>'

# Network access
allow dynamic-group txeventq-function-dg to use virtual-network-family
  in compartment <name>
```

**Scheduler Policy** (for Function invocation):
```hcl
# Allow Resource Scheduler to invoke function
allow dynamic-group txeventq-scheduler-dg to manage functions-family
  in compartment <name>
```

### Resource Principal Authentication

```java
// No API keys needed - function authenticates via instance principal
ResourcePrincipalAuthenticationDetailsProvider provider =
    ResourcePrincipalAuthenticationDetailsProvider.builder().build();

ObjectStorageClient client = ObjectStorageClient.builder()
    .build(provider);
```

## Deployment Architecture

### Terraform Structure

```
terraform/
├── main.tf          # Provider, backend config
├── variables.tf     # Input variables
├── outputs.tf       # Output values
├── network.tf       # VCN, subnets, gateways, NSGs
├── database.tf      # Autonomous Database
├── storage.tf       # Object Storage bucket
├── iam.tf           # Dynamic groups, policies
├── functions.tf     # Application, function, config
├── scheduler.tf     # Resource Scheduler schedule
└── compute.tf       # Compute instance for mailpit
```

### Ansible Structure

```
ansible/
├── inventory        # Compute instance IP
└── provision_mailpit.yaml
    ├── Install podman
    ├── Configure firewalld
    └── Create systemd service for mailpit
```

## Monitoring Architecture

### Resource Scheduler Configuration

```
Action: START_RESOURCE (invokes function)
Recurrence Type: CRON
Recurrence Details: 0 * * * *  # Every hour (configurable)
Resources: Function OCID
Note: Minimum interval is 1 hour per OCI limitations
```

### Logging Flow

```
Function Logs
  ├─> OCI Logging Service
  │   ├─> Log Group: /functions/<app-name>
  │   └─> Log: <function-name>
  └─> Search via OCI Logging Search
      ├─> Structured logs: "MESSAGE_PROCESSED | msgId=... | title=..."
      └─> Query: search "<compartment>/<log-group>" | "MESSAGE_PROCESSED"
```

### Metrics (OCI Monitoring)

```
Function Metrics:
├─> FunctionInvocations (count)
├─> FunctionDuration (ms, p50/p95/p99)
├─> FunctionErrors (count)
└─> FunctionConcurrency (count)

Custom Metrics (optional):
├─> MessagesProcessed (count)
├─> QueueDepth (gauge)
├─> FileUploadSuccess/Failure (count)
└─> EmailSendSuccess/Failure (count)
```

## Scalability Considerations

### Current Design (POC)

- **Concurrency**: 1 (single function instance)
- **Throughput**: ~5 messages/hour (1 invocation/hour \* 5 messages/batch)
- **Latency**: Up to 1 hour (scheduler frequency, configurable)
- **Note**: OCI Resource Scheduler minimum interval is 1 hour

### Scale-Up Options

1. **Increase Batch Size**: 10-20 messages (ensure < 180s timeout)
2. **Increase Concurrency**: 2-5 parallel instances (check queue depth)
3. **Adjust Schedule Frequency**: CRON expression for different intervals (minimum 1 hour)
4. **Add Connection Pooling**: Oracle UCP (for high-volume scenarios)
5. **Optimize Cold Starts**: Pre-warm containers, minimize wallet size

### Bottlenecks

- Function timeout: 180 seconds (hard limit)
- Database connection overhead:
  - LOCAL: ~500ms per cold start (direct connection)
  - OCI: ~100-200ms per cold start (DRCP reduces overhead)
- Email sending: ~100-200ms per email (sequential)
- Object Storage PUT: ~50-100ms per file

## Security Architecture

### Defense in Depth

**Layer 1: Network**

- Private subnets for functions (no public internet access)
- NSG rules (minimal required ports)
- NAT Gateway (outbound only)

**Layer 2: Authentication**

- ADB: mTLS with wallet (mutual TLS)
- OCI SDK: Resource Principal (no static credentials)
- SMTP: Plain Auth (username/password)

**Layer 3: Authorization**

- IAM Dynamic Group (scoped to compartment)
- Policies (least privilege, bucket-specific)

**Layer 4: Data Protection**

- Object Storage: Encryption at rest (Oracle-managed keys)
- Wallet: Encrypted, base64-encoded in function config
- Secrets: Function config (POC) or OCI Vault (production)

**Layer 5: Audit**

- Function logs (all operations logged)
- Database audit (optional PROCESSED_MESSAGES table)
- OCI Audit service (infrastructure changes)
