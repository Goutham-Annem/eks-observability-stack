##############################################################################
# eks-observability-stack — Terraform
# Deploys: cert-manager, OpenTelemetry Collector, Prometheus+Thanos,
#          Loki, Tempo, Grafana, AlertManager
##############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws        = { source = "hashicorp/aws",        version = ">= 5.0" }
    kubernetes = { source = "hashicorp/kubernetes",  version = ">= 2.20" }
    helm       = { source = "hashicorp/helm",        version = ">= 2.12" }
  }
}

locals {
  namespace = "monitoring"
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = local.namespace
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

##############################################################################
# S3 buckets for Thanos (metrics) and Loki (logs) long-term storage
##############################################################################
resource "aws_s3_bucket" "thanos" {
  bucket = "${var.cluster_name}-thanos-metrics"
  tags   = var.tags
}

resource "aws_s3_bucket" "loki" {
  bucket = "${var.cluster_name}-loki-logs"
  tags   = var.tags
}

resource "aws_s3_bucket_lifecycle_configuration" "thanos" {
  bucket = aws_s3_bucket.thanos.id
  rule {
    id     = "expire-old-metrics"
    status = "Enabled"
    expiration { days = var.metrics_retention_days }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration { days = var.logs_retention_days }
  }
}

##############################################################################
# IRSA for Thanos + Loki to access S3
##############################################################################
module "thanos_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-thanos"
  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${local.namespace}:thanos"]
    }
  }
  role_policy_arns = { s3 = aws_iam_policy.thanos_s3.arn }
}

resource "aws_iam_policy" "thanos_s3" {
  name = "${var.cluster_name}-thanos-s3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.thanos.arn, "${aws_s3_bucket.thanos.arn}/*"]
    }]
  })
}

module "loki_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-loki"
  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${local.namespace}:loki"]
    }
  }
  role_policy_arns = { s3 = aws_iam_policy.loki_s3.arn }
}

resource "aws_iam_policy" "loki_s3" {
  name = "${var.cluster_name}-loki-s3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.loki.arn, "${aws_s3_bucket.loki.arn}/*"]
    }]
  })
}

##############################################################################
# Helm releases
##############################################################################
resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.90.0"
  namespace  = local.namespace
  values     = [file("${path.module}/../helm/otel-values.yaml")]
  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.0.0"
  namespace  = local.namespace
  values     = [file("${path.module}/../helm/prometheus-values.yaml")]
  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.5.0"
  namespace  = local.namespace
  values     = [file("${path.module}/../helm/loki-values.yaml")]

  set {
    name  = "loki.storage.s3.bucketnames"
    value = aws_s3_bucket.loki.bucket
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.loki_irsa.iam_role_arn
  }
  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "7.3.0"
  namespace  = local.namespace
  values     = [file("${path.module}/../helm/grafana-values.yaml")]
  depends_on = [helm_release.kube_prometheus_stack, helm_release.loki]
}
