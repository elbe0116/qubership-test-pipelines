check_resources() {
    local namespace="$1"
    local all_ready=true

    dump_integration_test_log_tail() {
        local ns="$1"
        local pod
        while read -r pod; do
            [[ -z "$pod" ]] && continue
            if [[ "$pod" != *tests* ]]; then
                continue
            fi
            local phase
            phase=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            echo "::group::Integration tests pod: $pod (phase=$phase) — kubectl logs --tail=100"
            kubectl logs "$pod" -n "$ns" --tail=100 2>&1 || echo "(kubectl logs failed or no logs yet)"
            echo "::endgroup::"
        done < <(kubectl get pods --no-headers -o custom-columns=":metadata.name" -n "$ns" 2>/dev/null || true)
    }

    deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
    for deployment in $deployments; do
        ready=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath="{.status.readyReplicas}" 2>/dev/null)
        total=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath="{.status.replicas}" 2>/dev/null)
        ready=${ready:-0}
        total=${total:-0}
        if [[ "$ready" -ne "$total" ]] || [[ "$total" -le 0 ]]; then
            echo "Deployment $deployment is not ready: $ready/$total"
            all_ready=false
        fi
    done

    statefulsets=$(kubectl get statefulsets -n "$namespace" -o jsonpath="{.items[*].metadata.name}")
    for statefulset in $statefulsets; do
        ready=$(kubectl get statefulset "$statefulset" -n "$namespace" -o jsonpath="{.status.readyReplicas}" 2>/dev/null)
        total=$(kubectl get statefulset "$statefulset" -n "$namespace" -o jsonpath="{.status.replicas}" 2>/dev/null)
        ready=${ready:-0}
        total=${total:-0}
        if [[ "$ready" -ne "$total" ]] || [[ "$total" -le 0 ]]; then
            echo "StatefulSet $statefulset is not ready: $ready/$total"
            all_ready=false
        fi
    done

    daemonsets=$(kubectl get daemonsets -n "$namespace" -o jsonpath="{.items[*].metadata.name}")
    for daemonset in $daemonsets; do
        ready=$(kubectl get daemonset "$daemonset" -n "$namespace" -o jsonpath="{.status.numberReady}" 2>/dev/null)
        desired=$(kubectl get daemonset "$daemonset" -n "$namespace" -o jsonpath="{.status.desiredNumberScheduled}" 2>/dev/null)
        ready=${ready:-0}
        desired=${desired:-0}
        if [[ "$ready" -ne "$desired" ]] || [[ "$desired" -le 0 ]]; then
            echo "DaemonSet $daemonset is not ready: $ready/$desired"
            all_ready=false
        fi
    done

    if [ "$all_ready" = true ]; then
        #All resources are ready
        return 0
    else
        #Some resources are not ready — integration-tests runner is often 0/1 until Robot finishes; show log tail each poll
        dump_integration_test_log_tail "$namespace"
        #Some resources are not ready
        return 1
    fi
}

check_resources "$@"
