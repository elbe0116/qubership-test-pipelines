check_resources() {
    local namespace="$1"
    local all_ready=true
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    is_integration_tests_deployment() {
        [[ "$1" == *integration-tests* ]]
    }

    integration_tests_deployment_ok() {
        local ns="$1"
        local deployment="$2"
        local pod phase

        pod=$(kubectl get pods -n "$ns" -l "name=${deployment}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [[ -z "$pod" ]]; then
            echo "Deployment $deployment: no pod scheduled yet"
            return 1
        fi

        phase=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        case "$phase" in
            Running|Pending)
                echo "Deployment $deployment: pod $pod is $phase (0/1 ready until Robot tests finish — OK)"
                return 0
                ;;
            Succeeded)
                echo "Deployment $deployment: pod $pod Succeeded"
                return 0
                ;;
            *)
                echo "Deployment $deployment: pod $pod phase=$phase"
                return 1
                ;;
        esac
    }

    deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
    for deployment in $deployments; do
        if is_integration_tests_deployment "$deployment"; then
            if ! integration_tests_deployment_ok "$namespace" "$deployment"; then
                all_ready=false
            fi
            continue
        fi

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
        return 0
    else
        bash "$script_dir/dump_integration_test_logs.sh" "$namespace" 150
        return 1
    fi
}

check_resources "$@"
