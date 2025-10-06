# Terraform Deployment

## Setup

1. Copy example tfvars:
```bash
cp production.tfvars.example production.tfvars
```

2. Edit `production.tfvars` with your OCI details

3. Get tenancy namespace:
```bash
oci os ns get
```

## Deploy

```bash
terraform init
terraform plan -var-file=production.tfvars
terraform apply -var-file=production.tfvars
```

## Outputs

Save outputs for later use:
```bash
terraform output -json > outputs.json
```

Get wallet:
```bash
terraform output -raw wallet_base64 | base64 -d > wallet.zip
```

## Destroy

```bash
terraform destroy -var-file=production.tfvars
```
