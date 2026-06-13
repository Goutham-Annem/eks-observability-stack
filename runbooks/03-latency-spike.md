# Runbook: Latency Spike Investigation

**Alert:** `HighP99Latency` — p99 latency > 500ms for > 5 minutes  
**Severity:** Warning → Critical if sustained > 15 min  
**Owner:** Platform / SRE team

---

## 1. Immediate triage (< 2 min)

```bash
# Which services are affected?
kubectl top pods -A --sort-by=cpu | head -20

# Check HPA status — are we scaling?
kubectl get hpa -A

# Any recent rollouts?
kubectl rollout history deployment -A | grep -v "No rollout"
```

## 2. Identify the bottleneck

### Option A: Database slow queries
```bash
# Check RDS CloudWatch — look for DatabaseConnections spike
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --period 300 \
  --statistics Average \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Check PgBouncer pool saturation (if deployed)
kubectl exec -n data deploy/pgbouncer -- psql -h localhost -p 6432 pgbouncer -c "SHOW POOLS;"
```

### Option B: Memory pressure → GC pauses
```bash
# JVM services — check heap
kubectl exec -n <namespace> <pod> -- curl -s localhost:8080/actuator/metrics/jvm.memory.used

# Node-level memory
kubectl top nodes
```

### Option C: Network / service mesh issues
```bash
# Istio — check for circuit breaker trips
kubectl exec -n <namespace> deploy/<service> -c istio-proxy \
  -- pilot-agent request GET stats | grep "overflow\|pending"

# Check envoy upstream timeouts
kubectl exec -n <namespace> deploy/<service> -c istio-proxy \
  -- curl -s localhost:15000/clusters | grep cx_connect_fail
```

### Option D: Downstream dependency
```bash
# Trace a slow request with Tempo (via Grafana)
# Filter: service.name = "<your-service>" AND duration > 500ms

# Or check OpenTelemetry collector for dropped spans
kubectl logs -n monitoring deploy/otel-collector | grep "dropped\|error"
```

## 3. Mitigation options

| Root cause | Immediate action |
|------------|-----------------|
| Insufficient replicas | `kubectl scale deployment <name> --replicas=<N>` |
| DB connection pool exhausted | Increase PgBouncer pool_size or add read replica |
| Noisy neighbour on node | Add `priorityClass: high-priority` to affected workload |
| Recent bad deploy | `kubectl rollout undo deployment/<name>` |
| External dependency down | Enable circuit breaker / return cached response |

## 4. Post-incident

- Add a `SLO burn rate` alert if not present (alert before p99 breaches SLA)
- Review Grafana `Application RED Metrics` dashboard for the spike window
- File an incident report with timeline, root cause, and action items

---

*Runbook maintained by platform team. Last updated: 2026-06-13*
