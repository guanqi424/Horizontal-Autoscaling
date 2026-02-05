#!/usr/bin/env bash
set -euo pipefail

CTX="${CTX:-kind-cluster}"
NS="${NS:-default}"
HPA="${HPA:-example1-hpa}"
DEP="${DEP:-example1}"
LABEL="${LABEL:-app=example1}"
INTERVAL="${INTERVAL:-1}"
OUT="${OUT:-./collected_data/hpa_run_$(date +%Y%m%d_%H%M%S).csv}"

echo "ts,context,dep_replicas,dep_ready,hpa_current,hpa_desired,cpu_cur_util,cpu_target_util,pods_cpu_m_sum,pods_cpu_m_list,pods_mem_mi_sum,pods_mem_mi_list,lastScaleTime" > "$OUT"

while true; do
  ts="$(date -Iseconds)"

  hpa_json="$(kubectl --context "$CTX" -n "$NS" get hpa "$HPA" -o json)"
  dep_json="$(kubectl --context "$CTX" -n "$NS" get deploy "$DEP" -o json)"

  hpa_cur="$(echo "$hpa_json" | jq -r '.status.currentReplicas // 0')"
  hpa_des="$(echo "$hpa_json" | jq -r '.status.desiredReplicas // 0')"
  lastScaleTime="$(echo "$hpa_json" | jq -r '.status.lastScaleTime // ""')"

  cpu_cur_util="$(echo "$hpa_json" | jq -r '
    ([.status.currentMetrics[]? | select(.type=="Resource" and .resource.name=="cpu") | .resource.current.averageUtilization][0]) // ""')"
  cpu_target_util="$(echo "$hpa_json" | jq -r '
    ([.spec.metrics[]? | select(.type=="Resource" and .resource.name=="cpu") | .resource.target.averageUtilization][0]) // ""')"

  dep_rep="$(echo "$dep_json" | jq -r '.status.replicas // 0')"
  dep_ready="$(echo "$dep_json" | jq -r '.status.readyReplicas // 0')"

  # Sum pod CPU/mem from metrics-server (kubectl top)
  top_out="$(kubectl --context "$CTX" -n "$NS" top pods -l "$LABEL" --no-headers 2>/dev/null || true)"

  pods_cpu_m_sum="$(printf "%s\n" "$top_out" | awk '{gsub(/m/,"",$2); sum+=$2} END{print sum+0}')"

  pods_cpu_m_list="$(printf "%s\n" "$top_out" | awk '
    {
      cpu = $2
      item = $1 "=" cpu
      out = out (NR==1 ? "" : "; ") item
    }
    END{printf("%s", out)}
  ')"

  pods_mem_mi_sum="$(printf "%s\n" "$top_out" | awk '
    function toMi(x){
      if (x ~ /Ki$/){sub(/Ki$/,"",x); return x/1024}
      if (x ~ /Mi$/){sub(/Mi$/,"",x); return x}
      if (x ~ /Gi$/){sub(/Gi$/,"",x); return x*1024}
      sub(/[A-Za-z]+$/,"",x); return x
    }
    {sum+=toMi($3)}
    END{printf("%.3f", sum+0)}
  ')"

  pods_mem_mi_list="$(printf "%s\n" "$top_out" | awk '
    function toMi(x){
      if (x ~ /Ki$/){sub(/Ki$/,"",x); return x/1024}
      if (x ~ /Mi$/){sub(/Mi$/,"",x); return x}
      if (x ~ /Gi$/){sub(/Gi$/,"",x); return x*1024}
      sub(/[A-Za-z]+$/,"",x); return x
    }
    {
      memMi = toMi($3)
      item = $1 "=" sprintf("%.3fMi", memMi)
      out = out (NR==1 ? "" : "; ") item
    }
    END{printf("%s", out)}
  ')"

  echo "$ts,$CTX,$dep_rep,$dep_ready,$hpa_cur,$hpa_des,$cpu_cur_util,$cpu_target_util,$pods_cpu_m_sum,$pods_cpu_m_list,$pods_mem_mi_sum,$pods_mem_mi_list,$lastScaleTime" >> "$OUT"
  sleep "$INTERVAL"
done
