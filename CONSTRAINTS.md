# Constraints

## Design Constraints

### This is a Proof of Concept (POC)

- Focus on core functionality, not production-hardening
- Simplicity over enterprise patterns
- Direct implementation over abstraction layers
- Hardcoded reasonable defaults acceptable

### Single Responsibility

- Function does ONE thing: dequeue → process → notify
- No feature creep beyond core workflow
- No generalized queue processing framework
- No multi-tenant support

### No Premature Optimization

- No connection pooling (Oracle UCP) unless batch size requires it
- No caching layers
- No distributed tracing (APM/Zipkin)
- No custom metrics publishing (use OCI built-in only)
- No worker pools or async processing

### No Over-Engineering

- Static variables for connection reuse (not dependency injection)
- Direct JDBC, not ORM frameworks
- Simple string replacement for email templates (not templating engines)
- No microservices architecture
- No event sourcing or CQRS patterns

## Technology Constraints

### Required Technologies (Non-Negotiable)

- **Java 23**: No other languages
- **Fn Project**: No other function frameworks (AWS Lambda SDK, etc.)
- **Oracle Database TxEventQ**: No other message queues (Kafka, RabbitMQ, SQS)
- **OCI Functions**: No other serverless platforms
- **Terraform**: For infrastructure (not CloudFormation, ARM, Pulumi)

### Prohibited Technologies

- **No Kubernetes/Docker Compose** for local development
- **No Spring Boot/Quarkus/Micronaut**: Too heavy for serverless functions
- **No Hibernate/JPA**: Direct JDBC only
- **No Liquibase/Flyway**: SQL scripts executed manually
- **No Service Mesh** (Istio, Linkerd)
- **No API Gateway**: Function invoked directly by Notification Topic

### Version Constraints

- Java 23 only (not 17, 21, or other LTS versions)
- Oracle Database 23ai (not 19c, 21c)
- Fn Project (not OpenFaaS, Knative)

## Functional Constraints

### What NOT to Build

**No User Interface**:

- No web dashboard
- No admin console
- No message browser UI
- Configuration via Terraform/function config only

**No Authentication/Authorization Beyond Infrastructure**:

- No OAuth/OIDC for PAR links
- No JWT tokens
- No user management
- Rely on OCI IAM only

**No Advanced Queue Features**:

- No message priority (use default)
- No delayed messages
- No message routing/filtering
- No Dead Letter Queue (DLQ) in POC
- No consumer groups

**No Idempotency**:

- No duplicate message detection
- No processed message tracking (beyond optional logging table)
- Hash-based deduplication for files only (same content → same filename)

**No Retry Logic**:

- No exponential backoff
- No circuit breakers
- Failed messages remain in queue for next invocation (simple retry)

**No Data Transformation**:

- Message payload used as-is for file content
- No format conversion (JSON → XML, etc.)
- No content enrichment

**No Multi-Region**:

- Single OCI region deployment
- No cross-region replication
- No disaster recovery setup

## Operational Constraints

### No Production Hardening (POC Phase)

**Secrets Management**:

- Function config variables acceptable for POC
- OCI Vault integration optional (future enhancement)
- No HashiCorp Vault, AWS Secrets Manager, etc.

**High Availability**:

- No multi-AZ deployment
- No active-active setup
- Single function instance acceptable

**Backup/Recovery**:

- No automated database backups (beyond ADB defaults)
- No Point-in-Time Recovery (PITR) configuration
- No Object Storage versioning

**Monitoring**:

- OCI built-in metrics only
- No Prometheus/Grafana
- No custom dashboards
- No APM integration

**Logging**:

- `System.out.println()` acceptable
- No structured logging frameworks (Logback, Log4j2) required
- OCI Logging service only (no Splunk, ELK, Datadog)

### Scale Constraints

**Throughput Limits** (POC):

- Max ~60 messages/hour (12 invocations × 5 messages)
- No horizontal scaling (function concurrency = 1)
- No auto-scaling based on queue depth

**Message Size Limits**:

- Max message size: 1 MB (TxEventQ default)
- No large file handling (multi-part uploads)
- Content stored inline in message payload

**Batch Size Limits**:

- Max batch size: 20 messages (ensure < 180s timeout)
- No dynamic batch sizing
- No rate limiting

### Cost Constraints

**Target** (Enterprise POC):

- Minimize cost where possible
- No Always Free tier requirement
- No hard budget limit per month
- No premium OCI features (WAF, FastConnect, etc.)

**Resource Sizing**:

- ADB: Start with 1 OCPU (can scale as needed)
- Function: 256 MB memory (can adjust based on testing)
- Object Storage: Scale as needed

## Security Constraints

### What NOT to Implement

**Advanced Security**:

- No WAF (Web Application Firewall)
- No DDoS protection
- No SIEM integration
- No threat detection/response automation

**Data Protection**:

- No client-side encryption
- No bring-your-own-key (BYOK) for Object Storage
- No data masking/redaction
- No PII detection

**Compliance**:

- No HIPAA/PCI-DSS compliance requirements
- No audit log retention policies
- No data residency controls

**Network Security**:

- No VPN/FastConnect (public internet access to ADB acceptable)
- No private endpoints for Object Storage
- No DDoS mitigation

## Development Constraints

### Code Style

**Keep It Simple**:

- Single Java file acceptable (no package sprawl)
- Inline helper methods (no utils packages)
- No design patterns unless truly necessary
- No interfaces with single implementation

**No Testing Framework Requirement** (POC):

- JUnit optional
- Mockito optional
- No test coverage requirements
- Manual testing acceptable

**No CI/CD Pipeline** (POC):

- Manual build and deployment acceptable
- No Jenkins/GitLab CI/GitHub Actions required
- No automated testing gates
- No blue/green deployments

### Documentation

**Minimal Documentation**:

- README with setup instructions only
- No API documentation (no API)
- No architecture diagrams (text description acceptable)
- No runbooks (troubleshooting guide in IMPLEMENTATION.md)

**No User Documentation**:

- No end-user guides
- No video tutorials
- No FAQ

## Integration Constraints

### External Systems

**SMTP Only**:

- No SendGrid/Mailgun/SES integration
- No SMS notifications (Twilio)
- No Slack/Teams webhooks
- No push notifications

**Object Storage Only**:

- No S3 compatibility layer
- No Azure Blob Storage
- No Google Cloud Storage
- No SFTP/FTP upload

**Database Only**:

- No external data sources (REST APIs, GraphQL)
- No CDC (Change Data Capture) integration
- No database replication

## Performance Constraints

### Acceptable Latency

**Processing Latency**:

- End-to-end: < 5 minutes (alarm frequency)
- Function execution: < 180 seconds (timeout)
- Email delivery: Best effort (no SLA)

**No Performance Testing**:

- No load testing framework (JMeter, Gatling)
- No stress testing
- No performance benchmarking

**No Profiling**:

- No JProfiler/VisualVM
- No flame graphs
- No memory leak detection

## Change Management

### Version Control

**Minimal Git Workflow**:

- No GitFlow or trunk-based development
- No pull request templates
- No code review requirements
- No branching strategy

**No Release Management**:

- No semantic versioning
- No changelogs
- No release notes
- No rollback procedures

## What NOT to Worry About (Yet)

- Message ordering guarantees
- Exactly-once delivery
- Distributed transactions
- Saga pattern
- Event replay
- Schema evolution
- Backward compatibility
- API versioning
- Rate limiting per user
- Quota management
- Multi-tenancy
- Feature flags
- A/B testing
- Canary deployments
- Chaos engineering
- Container security scanning
- Dependency vulnerability scanning
- License compliance checking

---

## Philosophy

> "Do the simplest thing that could possibly work."

- Start with hardcoded values, extract to config only when needed
- Add abstractions when you have 3+ similar implementations, not before
- Build for today's requirements, not imagined future needs
- Choose boring, proven technology over new, exciting technology
- Optimize for iteration speed, not theoretical scalability
- Ship working code, then improve based on actual usage

## When to Violate These Constraints

Only violate these constraints when:

1. **Explicit requirement change**: User explicitly requests a feature
2. **Blocking issue**: Constraint prevents core functionality from working
3. **Security vulnerability**: Critical security issue discovered
4. **Production migration**: Moving from POC to production with specific SLAs

Otherwise, stick to the constraints. They exist to keep the project focused and deliverable.
