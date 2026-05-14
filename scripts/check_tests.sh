check_tests() {
    local namespace="$1"
    local file_name="artifacts/${namespace}_tests.txt"
    local IFS=" "
    local -a pods
    IFS=" " read -ra pods <<< "$(kubectl get pods --no-headers -o custom-columns=":metadata.name" -n "$namespace" | tr "\n" " ")"
    local test_pod=""

    for pod in "${pods[@]}"; do
      if [[ "$pod" == *"tests"* ]]; then
        test_pod="$pod"
        break
      fi
    done

    if ! [[ "$test_pod" ]]; then
      echo "::warning:: ℹ️ check_tests set to 'true', but there is no test pod"
      exit 0
    fi

    echo "Test pod found: $test_pod"

    status=$(kubectl get pod "$test_pod" -n "$namespace" -o jsonpath="{.status.phase}")
    echo "Pod status: $status"

    # Avoid pulling unbounded logs on every poll (slow + huge in Actions UI / memory).
    # Robot "Report: ... html" appears near the end; a large tail is enough to detect completion.
    local logs
    logs=$(kubectl logs "$test_pod" -n "$namespace" --tail=12000 2>/dev/null || true)
    if [[ "$logs" =~ Report.*html ]]; then
      mkdir -p "$(dirname "$file_name")" 2>/dev/null || true
      echo "$logs" > "$file_name"
      echo "📄 TEST LOGS:"
      echo "$logs"

      if ! kubectl cp "$test_pod":/opt/robot/output artifacts/robot-results/opt -n "$namespace"; then
        echo "::warning:: ⚠️ Failed to copy robot results"
      else
        echo "Robot results copied successfully"
      fi

      if ! kubectl cp "$test_pod":/tmp/clone artifacts/robot-results/tmp -n "$namespace"; then
        echo "tmp folder is empty"
      else
        echo "Robot results from tmp folder copied successfully"
      fi

      if [[ "$logs" == *"| FAIL |"* ]]; then
        #Tests failed
        exit 2
      else
        #Tests passed successfully
        exit 0
      fi
    else
       #Tests are still running — show recent output in CI each poll (same tail window)
       echo "⏳ Tests still in progress — last 80 lines of logs (tail=12000 window):"
       echo "$logs" | tail -n 80
       exit 1
    fi
}

check_tests "$@"
