#!/usr/bin/env bash
# Print integration-tests runner diagnostics in CI (collapsible ::group:: blocks).
set -euo pipefail

namespace="${1:?namespace required}"
tail_lines="${2:-150}"

is_test_pod() {
  [[ "$1" == *integration-tests* || "$1" == *tests* ]]
}

while read -r pod; do
  [[ -z "$pod" ]] && continue
  is_test_pod "$pod" || continue

  phase=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  ready=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "?")
  restarts=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "?")

  echo "::group::Integration tests pod: $pod (phase=$phase ready=$ready restarts=$restarts)"
  echo "--- kubectl describe pod/$pod (events) ---"
  kubectl describe pod "$pod" -n "$namespace" 2>&1 | tail -n 40 || true
  echo "--- kubectl logs --tail=$tail_lines ---"
  kubectl logs "$pod" -n "$namespace" --tail="$tail_lines" 2>&1 \
    || kubectl logs "$pod" -n "$namespace" --tail="$tail_lines" --previous 2>&1 \
    || echo "(no logs yet)"
  echo "::endgroup::"
done < <(kubectl get pods --no-headers -o custom-columns=":metadata.name" -n "$namespace" 2>/dev/null || true)
