# TxEventQ Function

Java 23 serverless function to process Oracle TxEventQ messages.

## Build

```bash
fn build
```

## Local Deploy

```bash
fn deploy --app txeventq-local --local
```

## Configure

See LOCAL.md for local configuration or CLOUD.md for OCI configuration.

## Test

```bash
echo '{}' | fn invoke txeventq-local txeventq-processor
```

## Push to OCIR

```bash
docker login <region>.ocir.io -u '<tenancy-namespace>/<username>'
fn push --registry <region>.ocir.io/<tenancy-namespace>/txeventq-processor
```
