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
