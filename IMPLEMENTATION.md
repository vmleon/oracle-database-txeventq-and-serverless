# Implementation Details

## Prerequisites

### Required Software

- Java 23
- Gradle
- Fn CLI
- Podman (with machine initialized and running)
- OCI CLI
- Terraform
- Ansible

## Phase 1: Local Development Setup

### 1.1 Start Local Containers

**Oracle Database FREE**:
```bash
podman run -d --name oracle-db \
  -p 1521:1521 \
  -e ORACLE_PWD=YourPassword123 \
  container-registry.oracle.com/database/free:latest

# Wait ~2-3 minutes for database to be ready
podman logs -f oracle-db  # Watch for "DATABASE IS READY TO USE!"
```

**Mailpit SMTP**:
```bash
podman run -d --name mailpit \
  -p 1025:1025 \
  -p 8025:8025 \
  axllent/mailpit:latest

# Access UI at http://localhost:8025
```

### 1.2 Database Setup

**Create User** (`db/01_create_user.sql`):
```sql
-- Connect as PDBADMIN (default user for FREEPDB1)
-- No user creation needed for local deployment
-- PDBADMIN already has necessary privileges
```

**Create Queue** (`db/02_create_queue.sql`):
```sql
-- Connect as PDBADMIN
BEGIN
    DBMS_AQADM.STOP_QUEUE(queue_name => 'REPORT_QUEUE');
    DBMS_AQADM.DROP_QUEUE(queue_name => 'REPORT_QUEUE');
    DBMS_AQADM.DROP_QUEUE_TABLE(queue_table => 'REPORT_QUEUE_TABLE');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

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

BEGIN
    DBMS_AQADM.START_QUEUE(queue_name => 'REPORT_QUEUE');
END;
/

BEGIN
    DBMS_AQADM.SET_QUEUE_TABLE_PROPERTY(
        queue_table => 'REPORT_QUEUE_TABLE',
        property => 'RETENTION_TIME',
        value => '604800'  -- 7 days
    );
END;
/

SELECT queue_name, queue_type, enqueue_enabled, dequeue_enabled
FROM USER_QUEUES
WHERE queue_name = 'REPORT_QUEUE';
```

**Enqueue Test Messages** (`db/03_enqueue_test_messages.sql`):
```sql
-- Connect as PDBADMIN
DECLARE
    enqueue_options    DBMS_AQ.ENQUEUE_OPTIONS_T;
    message_properties DBMS_AQ.MESSAGE_PROPERTIES_T;
    message_handle     RAW(16);
    message            JSON;
BEGIN
    message := JSON('{"title": "Monthly Sales Report", "content": "Sales data for January 2025...", "date": "2025-01-15T10:30:00Z"}');

    DBMS_AQ.ENQUEUE(
        queue_name         => 'REPORT_QUEUE',
        enqueue_options    => enqueue_options,
        message_properties => message_properties,
        payload            => message,
        msgid              => message_handle
    );

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

**Execute Setup**:
```bash
# Grant permissions (connect as SYS)
sql sys/YourPassword123@//localhost:1521/FREEPDB1 as sysdba @db/01_grant_permissions.sql

# Connect and run scripts as PDBADMIN
sql pdbadmin/YourPassword123@//localhost:1521/FREEPDB1 @db/02_create_queue.sql
sql pdbadmin/YourPassword123@//localhost:1521/FREEPDB1 @db/03_enqueue_test_messages.sql
```

### 1.3 Function Implementation

**Directory Structure**:
```
function/
├── src/
│   └── main/
│       ├── java/com/oracle/fn/
│       │   └── TxEventQProcessor.java
│       └── resources/
│           └── email-template.html
├── build.gradle
└── func.yaml
```

**build.gradle**:
```gradle
plugins {
    id 'java'
}

group = 'com.oracle.fn'
version = '1.0-SNAPSHOT'

sourceCompatibility = '23'
targetCompatibility = '23'

repositories {
    mavenCentral()
}

dependencies {
    // Fn Framework
    implementation 'com.fnproject.fn:api:1.0.190'

    // Oracle JDBC
    implementation 'com.oracle.database.jdbc:ojdbc11:23.3.0.23.09'
    implementation 'com.oracle.database.security:oraclepki:23.3.0.23.09'
    implementation 'com.oracle.database.security:osdt_cert:23.3.0.23.09'
    implementation 'com.oracle.database.security:osdt_core:23.3.0.23.09'

    // OCI SDK (Resource Principal, Object Storage, PAR)
    implementation 'com.oracle.oci.sdk:oci-java-sdk-common:3.30.0'
    implementation 'com.oracle.oci.sdk:oci-java-sdk-objectstorage:3.30.0'
    implementation 'com.oracle.oci.sdk:oci-java-sdk-addons-resteasy-client-configurator:3.30.0'

    // Jakarta Mail
    implementation 'jakarta.mail:jakarta.mail-api:2.1.2'
    implementation 'org.eclipse.angus:angus-mail:2.0.2'

    // JSON processing
    implementation 'com.fasterxml.jackson.core:jackson-databind:2.16.0'

    // Logging
    implementation 'org.slf4j:slf4j-api:2.0.9'
    implementation 'org.slf4j:slf4j-simple:2.0.9'
}

jar {
    manifest {
        attributes 'Main-Class': 'com.oracle.fn.TxEventQProcessor'
    }
}
```

**func.yaml**:
```yaml
schema_version: 20180708
name: txeventq-processor
version: 0.0.1
runtime: java
build_image: fnproject/fn-java-fdk-build:jdk23
run_image: fnproject/fn-java-fdk:jre23
cmd: com.oracle.fn.TxEventQProcessor::handleRequest
```

**TxEventQProcessor.java** (Core Implementation):
```java
package com.oracle.fn;

import com.fnproject.fn.api.FnConfiguration;
import com.fnproject.fn.api.RuntimeContext;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.*;
import com.oracle.bmc.objectstorage.responses.*;
import com.oracle.bmc.objectstorage.model.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.mail.*;
import jakarta.mail.internet.*;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.sql.*;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.Date;
import java.util.zip.*;

public class TxEventQProcessor {
    private static Connection dbConnection;
    private static ObjectStorageClient osClient;
    private static String environment;
    private static final ObjectMapper objectMapper = new ObjectMapper();

    @FnConfiguration
    public void configure(RuntimeContext ctx) {
        environment = ctx.getConfigurationByKey("ENVIRONMENT").orElse("DEVELOPMENT");

        if ("PRODUCTION".equals(environment)) {
            extractWallet(ctx);
            initializeOciClient();
        }
    }

    public String handleRequest(String input) {
        try {
            Connection conn = getConnection();
            int processed = processMessages(conn);
            return String.format("Processed %d messages", processed);
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
            return "Error: " + e.getMessage();
        }
    }

    private Connection getConnection() throws SQLException {
        if (dbConnection == null || !dbConnection.isValid(5)) {
            String connStr = System.getenv("DB_CONNECTION_STRING");
            String username = System.getenv("DB_USERNAME");
            String password = System.getenv("DB_PASSWORD");

            Properties props = new Properties();
            props.put("user", username);
            props.put("password", password);

            // DRCP pooling for Production (OCI) environment
            if ("PRODUCTION".equals(environment)) {
                props.put("oracle.jdbc.DRCPConnectionClass", "TXEVENTQ_CLASS");
            }

            dbConnection = DriverManager.getConnection(connStr, props);
        }
        return dbConnection;
    }

    private int processMessages(Connection conn) throws Exception {
        int processed = 0;
        int batchSize = Integer.parseInt(System.getenv("BATCH_SIZE"));
        String queueName = System.getenv("QUEUE_NAME");

        // Use DBMS_AQ API directly for TxEventQ
        String dequeueSQL = "DECLARE " +
            "  dequeue_options DBMS_AQ.DEQUEUE_OPTIONS_T; " +
            "  message_properties DBMS_AQ.MESSAGE_PROPERTIES_T; " +
            "  message_handle RAW(16); " +
            "  message JSON; " +
            "BEGIN " +
            "  dequeue_options.dequeue_mode := DBMS_AQ.REMOVE; " +
            "  dequeue_options.visibility := DBMS_AQ.ON_COMMIT; " +
            "  dequeue_options.wait := DBMS_AQ.NO_WAIT; " +
            "  DBMS_AQ.DEQUEUE( " +
            "    queue_name => ?, " +
            "    dequeue_options => dequeue_options, " +
            "    message_properties => message_properties, " +
            "    payload => message, " +
            "    msgid => message_handle " +
            "  ); " +
            "  ? := message.to_string(); " +
            "EXCEPTION " +
            "  WHEN OTHERS THEN " +
            "    ? := NULL; " +
            "END;";

        try (CallableStatement stmt = conn.prepareCall(dequeueSQL)) {
            for (int i = 0; i < batchSize; i++) {
                stmt.setString(1, queueName);
                stmt.registerOutParameter(2, Types.CLOB);
                stmt.registerOutParameter(3, Types.VARCHAR);

                try {
                    stmt.execute();
                    String jsonPayload = stmt.getString(2);

                    if (jsonPayload == null || jsonPayload.trim().isEmpty()) {
                        break; // Queue is empty
                    }

                    processMessage(jsonPayload);
                    processed++;
                } catch (SQLException e) {
                    // Queue empty or error
                    if (e.getMessage().contains("ORA-25228")) {
                        break; // No more messages
                    }
                    System.err.println("Error dequeuing message: " + e.getMessage());
                }
            }
        }

        conn.commit();
        return processed;
    }

    private void processMessage(String jsonPayload) throws Exception {
        JsonNode node = objectMapper.readTree(jsonPayload);
        String title = node.get("title").asText();
        String content = node.get("content").asText();
        String date = node.get("date").asText();

        String sanitizedTitle = title.replaceAll("[/\\\\:*?\"<>|]", "_");
        String hash = generateHash(content);
        String filename = sanitizedTitle + "_" + hash + ".txt";

        String downloadLink;
        if ("PRODUCTION".equals(environment)) {
            downloadLink = uploadToObjectStorageAndCreatePar(filename, content.getBytes());
        } else {
            downloadLink = saveToLocalDirectory(filename, content);
        }

        sendEmail(downloadLink, title, date);

        System.out.println(String.format(
            "MESSAGE_PROCESSED | title=%s | filename=%s | date=%s",
            title, filename, date
        ));
    }

    private String generateHash(String content) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] hash = digest.digest(content.getBytes(StandardCharsets.UTF_8));
        return bytesToHex(hash).substring(0, 8);
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    private String saveToLocalDirectory(String filename, String content) throws IOException {
        String localDir = System.getenv("LOCAL_TEMP_DIR");
        Path filePath = Paths.get(localDir, filename);
        Files.createDirectories(filePath.getParent());
        Files.writeString(filePath, content);
        return "file://" + filePath.toAbsolutePath();
    }

    private String uploadToObjectStorageAndCreatePar(String filename, byte[] content) {
        String namespace = System.getenv("OBJECT_STORAGE_NAMESPACE");
        String bucketName = System.getenv("BUCKET_NAME");

        // Upload object
        PutObjectRequest putRequest = PutObjectRequest.builder()
            .namespaceName(namespace)
            .bucketName(bucketName)
            .objectName(filename)
            .putObjectBody(new ByteArrayInputStream(content))
            .build();
        osClient.putObject(putRequest);

        // Create PAR
        int validityDays = Integer.parseInt(System.getenv("PAR_VALIDITY_DAYS"));
        Date expirationDate = Date.from(Instant.now().plus(validityDays, ChronoUnit.DAYS));

        CreatePreauthenticatedRequestDetails parDetails =
            CreatePreauthenticatedRequestDetails.builder()
                .name("PAR_" + filename)
                .objectName(filename)
                .accessType(CreatePreauthenticatedRequestDetails.AccessType.ObjectRead)
                .timeExpires(expirationDate)
                .build();

        CreatePreauthenticatedRequestRequest parRequest =
            CreatePreauthenticatedRequestRequest.builder()
                .namespaceName(namespace)
                .bucketName(bucketName)
                .createPreauthenticatedRequestDetails(parDetails)
                .build();

        CreatePreauthenticatedRequestResponse response =
            osClient.createPreauthenticatedRequest(parRequest);

        String region = System.getenv("OCI_REGION");
        return "https://objectstorage." + region + ".oraclecloud.com" +
               response.getPreauthenticatedRequest().getFullPath();
    }

    private void sendEmail(String downloadLink, String title, String date) throws Exception {
        Properties props = new Properties();
        props.put("mail.smtp.host", System.getenv("SMTP_HOST"));
        props.put("mail.smtp.port", System.getenv("SMTP_PORT"));
        props.put("mail.smtp.auth", "true");

        Session session = Session.getInstance(props, new Authenticator() {
            protected PasswordAuthentication getPasswordAuthentication() {
                return new PasswordAuthentication(
                    System.getenv("SMTP_USERNAME"),
                    System.getenv("SMTP_PASSWORD")
                );
            }
        });

        String htmlTemplate = loadTemplate();
        String htmlBody = htmlTemplate
            .replace("{DATE}", date)
            .replace("{TITLE}", title)
            .replace("{DOWNLOAD_LINK}", downloadLink);

        Message message = new MimeMessage(session);
        message.setFrom(new InternetAddress(System.getenv("SENDER_EMAIL")));
        message.setRecipients(
            Message.RecipientType.TO,
            InternetAddress.parse(System.getenv("RECIPIENT_EMAILS"))
        );
        message.setSubject("Data Safe Report");
        message.setContent(htmlBody, "text/html; charset=utf-8");

        Transport.send(message);
    }

    private String loadTemplate() throws IOException {
        try (InputStream is = getClass().getResourceAsStream("/email-template.html")) {
            return new String(is.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private void extractWallet(RuntimeContext ctx) {
        File walletDir = new File("/tmp/wallet");
        if (walletDir.exists()) return;

        walletDir.mkdirs();

        String walletBase64 = ctx.getConfigurationByKey("WALLET_BASE64")
            .orElseThrow(() -> new RuntimeException("WALLET_BASE64 not configured"));

        byte[] walletZip = Base64.getDecoder().decode(walletBase64);

        try (ByteArrayInputStream bis = new ByteArrayInputStream(walletZip);
             ZipInputStream zis = new ZipInputStream(bis)) {
            ZipEntry entry;
            while ((entry = zis.getNextEntry()) != null) {
                File file = new File(walletDir, entry.getName());
                try (FileOutputStream fos = new FileOutputStream(file)) {
                    zis.transferTo(fos);
                }
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to extract wallet", e);
        }

        System.setProperty("oracle.net.tns_admin", "/tmp/wallet");
        System.setProperty("oracle.net.wallet_location", "/tmp/wallet");
    }

    private void initializeOciClient() {
        ResourcePrincipalAuthenticationDetailsProvider provider =
            ResourcePrincipalAuthenticationDetailsProvider.builder().build();
        osClient = ObjectStorageClient.builder().build(provider);
    }
}
```

**email-template.html** (`src/main/resources/email-template.html`):
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        h2 { color: #333; }
        .download-btn {
            display: inline-block;
            padding: 10px 20px;
            background-color: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 5px;
            margin-top: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h2>Data Safe Report</h2>
        <p><strong>Date:</strong> {DATE}</p>
        <p>A new report is available for download:</p>
        <p><a href="{DOWNLOAD_LINK}" class="download-btn">Download {TITLE}</a></p>
        <p><small>This is an automated message. Please do not reply.</small></p>
    </div>
</body>
</html>
```

### 1.4 Deploy and Test Locally

**Start Fn Server**:
```bash
fn start -d
```

**Build and Deploy Function**:
```bash
cd function
fn deploy --app txeventq-local --local
```

**Configure Function**:
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

**Invoke Function**:
```bash
echo '{}' | fn invoke txeventq-local txeventq-processor
```

**Verify**:
- Check function output: `Processed 2 messages`
- Check files: `ls /tmp/reports/`
- Check emails: `open http://localhost:8025`

## Phase 2: OCI Infrastructure

### 2.1 Terraform Configuration

**variables.tf**:
```hcl
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "region" {}

variable "vcn_cidr" { default = "10.0.0.0/16" }
variable "public_subnet_cidr" { default = "10.0.1.0/24" }
variable "private_subnet_cidr" { default = "10.0.2.0/24" }

variable "adb_db_name" { default = "txeventqdb" }
variable "adb_display_name" { default = "TxEventQ DB" }
variable "adb_admin_password" { sensitive = true }
variable "adb_wallet_password" { sensitive = true }

variable "bucket_name" { default = "txeventq-reports" }
variable "queue_name" { default = "REPORT_QUEUE" }
variable "batch_size" { default = "5" }
variable "par_validity_days" { default = "7" }

variable "smtp_username" {}
variable "smtp_password" { sensitive = true }
variable "sender_email" {}
variable "recipient_emails" {}

variable "db_username" { default = "ADMIN" }
variable "db_password" { sensitive = true }

variable "function_memory_mb" { default = 256 }
variable "ocir_region" {}
variable "tenancy_namespace" {}
variable "ocir_repo" {}
variable "image_tag" { default = "latest" }

variable "schedule_cron_expression" { default = "0 * * * *" }  # Every hour
variable "schedule_display_name" { default = "txeventq-function-schedule" }
variable "schedule_description" { default = "Periodic schedule to invoke TxEventQ processor function" }
```

**network.tf**:
```hcl
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "txeventq-vcn"
  dns_label      = "txeventq"
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "txeventq-igw"
}

resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "txeventq-nat"
}

resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "txeventq-sgw"

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.public_subnet_cidr
  display_name      = "txeventq-public-subnet"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_subnet_cidr
  display_name               = "txeventq-private-subnet"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "txeventq-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "txeventq-private-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    network_entity_id = oci_core_service_gateway.main.id
  }
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}
```

**database.tf**:
```hcl
resource "oci_database_autonomous_database" "main" {
  compartment_id           = var.compartment_ocid
  db_name                  = var.adb_db_name
  display_name             = var.adb_display_name
  admin_password           = var.adb_admin_password
  db_workload              = "OLTP"
  is_auto_scaling_enabled  = false
  cpu_core_count           = 1
  data_storage_size_in_tbs = 1
  is_free_tier             = false
  license_model            = "LICENSE_INCLUDED"
}

data "oci_database_autonomous_database_wallet" "main" {
  autonomous_database_id = oci_database_autonomous_database.main.id
  password               = var.adb_wallet_password
  base64_encode_content  = true
}
```

**Deploy**:
```bash
cd terraform
terraform init
terraform plan -var-file=production.tfvars
terraform apply -var-file=production.tfvars
```

### 2.2 Build and Push Function to OCIR

```bash
# Login to OCIR
docker login <region>.ocir.io -u '<tenancy-namespace>/<username>'

# Build function
cd function
fn build

# Push to OCIR
fn push --registry <region>.ocir.io/<tenancy-namespace>/<repo-name>
```

### 2.3 Setup Database on ADB

```bash
# Download wallet (or use Terraform output)
# Connect and run scripts as ADMIN
sql ADMIN/<password>@<adb_connection_string> @db/02_create_queue.sql
```

**DRCP Configuration** (Autonomous Database):

DRCP (Database Resident Connection Pooling) is automatically enabled on Autonomous Database. No manual setup required. The connection string must use the `:POOLED` suffix:

```
# Example DRCP connection string for ADB
jdbc:oracle:thin:@txeventqdb_high?TNS_ADMIN=/tmp/wallet:POOLED
```

The function code automatically sets the DRCP connection class (`TXEVENTQ_CLASS`) when `ENVIRONMENT=PRODUCTION`.

## Monitoring and Troubleshooting

### Check Queue Depth
```sql
SELECT COUNT(*) FROM AQ$REPORT_QUEUE_TABLE;
```

### Check Function Logs
```bash
oci logging-search search-logs \
  --search-query "search \"<compartment>/<log-group>\" | source='<function-ocid>'" \
  --time-start 2025-01-01T00:00:00Z
```

### Test Function Locally
```bash
echo '{}' | fn invoke txeventq-local txeventq-processor
```

### Common Issues

**Wallet Extraction Fails**:
- Verify base64 encoding: `base64 -d wallet_base64.txt > wallet_test.zip && unzip -t wallet_test.zip`
- Check function memory (256MB minimum)

**Database Connection Timeout**:
- Verify NSG rules allow function → ADB:1522
- Check NAT Gateway configured in private subnet route table
- Verify TNS_ADMIN system property set correctly
- Ensure connection string uses `:POOLED` suffix for DRCP (Production only)

**Email Not Sent**:
- Check mailpit logs: `podman logs mailpit`
- Verify SMTP credentials in function config
- Test SMTP connectivity: `telnet <smtp-host> 1025`
