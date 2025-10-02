# Project Documentation

This project has been organized into focused documents:

## 📋 [REQUIREMENTS.md](./REQUIREMENTS.md)
**What you're building**
- Objective and functional requirements
- Message format and configuration parameters
- Success criteria
- Explicitly defined out-of-scope items

## 🏗️ [ARCHITECTURE.md](./ARCHITECTURE.md)
**How it fits together**
- System overview and execution modes
- Network architecture and data flow
- Component architecture and deployment structure
- IAM and security architecture
- Scalability considerations

## 🔧 [IMPLEMENTATION.md](./IMPLEMENTATION.md)
**Specific technical details**
- Prerequisites and installation
- Phase-by-phase implementation guide
- Complete code examples (SQL, Java, Terraform)
- Deployment procedures
- Monitoring and troubleshooting

## 🚫 [CONSTRAINTS.md](./CONSTRAINTS.md)
**What NOT to do**
- Design and technology constraints
- Prohibited technologies and patterns
- What NOT to build (POC scope boundaries)
- Operational and security limits
- When to violate constraints

---

## Quick Navigation

**Getting Started?** → Start with [REQUIREMENTS.md](./REQUIREMENTS.md)

**Understanding the design?** → Read [ARCHITECTURE.md](./ARCHITECTURE.md)

**Ready to build?** → Follow [IMPLEMENTATION.md](./IMPLEMENTATION.md)

**Scope questions?** → Check [CONSTRAINTS.md](./CONSTRAINTS.md)

---

## Project Summary

**Goal**: Process messages from Oracle Database TxEventQ using OCI Serverless Functions, store content in Object Storage, and send email notifications with Pre-Authenticated Request (PAR) links.

**Key Technologies**: Oracle Autonomous Database 23ai, OCI Functions, Java 23, Fn Project, Terraform

**Deployment Modes**:
- Local development (Podman containers)
- OCI production (Terraform-managed infrastructure)

**Estimated Cost**: ~$25-30/month (POC)
