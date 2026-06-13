# eks-observability-stack

> Full-stack observability for EKS: OpenTelemetry → Prometheus → Grafana + Loki. Deploy in 15 minutes with Terraform + Helm.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## What's inside

| Component | Role |
|-----------|------|
| **OpenTelemetry Collector** | Unified ingestion — metrics, traces, logs from all workloads |
| **Prometheus + Thanos** | Long-term metrics storage with multi-cluster federation |
| **Grafana** | Dashboards wired to Prometheus + Loki |
| **Loki** | Log aggregation via Promtail DaemonSet |
| **Tempo** | Distributed tracing backend |
| **AlertManager** | PagerDuty / Slack routing |

## Architecture

```
Workloads (instrumented with OTel SDK)
        │  metrics/traces/logs
        ▼
┌─────────────────────────────────────────────┐
│         OpenTelemetry Collector (DaemonSet) │
│  pipelines: metrics→Prometheus              │
│             traces→Tempo                    │
│             logs→Loki                       │
└──────────┬──────────────┬───────────────────┘
           │              │
     ┌─────▼─────┐  ┌─────▼──────┐
     │ Prometheus│  │    Loki    │
     │  + Thanos │  │ (S3 backend│
     └─────┬─────┘  └─────┬──────┘
           │              │
           └──────┬───────┘
                  ▼
            ┌─────────┐
            │ Grafana │◄── Tempo (traces)
            └─────────┘
```

## Quick Start

```bash
# 1. Deploy with Terraform
cd terraform/
terraform init
terraform apply -var="cluster_name=my-cluster" -var="region=us-east-1"

# 2. Access Grafana
kubectl port-forward svc/grafana 3000:80 -n monitoring
# Open http://localhost:3000 (admin / see terraform output for password)
```

## Folder structure

```
eks-observability-stack/
├── terraform/          # Full IaC — namespaces, IRSA, Helm releases
├── helm/
│   ├── otel-values.yaml
│   ├── prometheus-values.yaml
│   ├── loki-values.yaml
│   └── grafana-values.yaml
└── runbooks/
    ├── 01-high-memory-alert.md
    ├── 02-pod-crashloop.md
    ├── 03-latency-spike.md
    └── 04-disk-pressure.md
```

## Pre-built Grafana Dashboards

- **EKS Cluster Overview** — node CPU/mem/disk, pod counts, pending pods
- **Namespace Cost Breakdown** — estimated spend per namespace (integrates with Kubecost)
- **Application RED Metrics** — Rate, Errors, Duration per service
- **Loki Log Explorer** — pre-configured log streams per namespace
- **Karpenter Node Lifecycle** — provisioning events, drift, disruptions

## IRSA Permissions Required

```hcl
# Thanos needs S3 for long-term storage
actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]

# Loki needs S3 as well
actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
```

## Alerting Rules Included

- Pod CrashLooping (> 3 restarts in 10m)
- Node memory > 85%
- PVC > 80% full
- API server latency p99 > 1s
- Karpenter provisioning failures
- Certificate expiry < 14 days

## License

MIT — by [Goutham Annem](https://linkedin.com/in/goutham-annem)
