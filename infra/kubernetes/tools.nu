export def find_chart_repos [] {
  [
    ["name" "url"]
    ;
    ["jetstack" "https://charts.jetstack.io"]
    ["minio-legacy" "https://helm.min.io/"]
    ["grafana"  "https://grafana.github.io/helm-charts"]
    ["prometheus-community"  "https://prometheus-community.github.io/helm-charts"]
    ["open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts"]
    ["linkerd" "https://helm.linkerd.io/stable"]
  ]
}

export def find_charts [] {
  [
    ["name"                    "repo_name"            "dependencies"]
    ;
    ["cert-manager"            "jetstack"             []]
    ["minio"                   "minio-legacy"         []]
    ["grafana"                 "grafana"              []]
    ["kube-prometheus-stack"   "prometheus-community" ["grafana"]]
    ["loki-distributed"        "grafana"              ["minio" "grafana"]]
    ["promtail"                "grafana"              ["loki-distributed"]]
    ["tempo-distributed"       "grafana"              ["minio" "grafana"]]
    # ["opentelemetry-collector" "open-telemetry"       ["cert-manager" "tempo-distributed"]]
    ["opentelemetry-operator" "open-telemetry"       ["cert-manager" "tempo-distributed"]]
    ["linkerd"                 "linkerd"              []]
    ["linkerd-viz"             "linkerd"              ["linkerd" "grafana" "kube-prometheus-stack"]]
    # ["linkerd-jaeger"          "linkerd"              ["linkerd" "opentelemetry-collector"]]
  ]
}

export def find_current_cluster [] {
  kubectl config view --minify -o jsonpath='{.clusters[].name}' | str trim -c "'"
}

def install_helm [] {
  if (which helm | empty?) {
    echo "try to install 'helm' via brew"
    do -i { brew install helm } | complete
  }
}

def find_tools_cache_dir [] {
  "/tmp/tools/test"
}

def compute_changeid [pattern: string] {
  # glob pattern | sort | wrap path | upsert hash {|it| open --raw $it.path | hash sha256}
  # create a hash by reducing like a blockchain
  glob $pattern | sort | where ($it | path type) == "file" | reduce -f "" {|it,acc| $"($acc)+(open --raw $it | hash sha256)" | hash sha256}
}

export def make_taskinput [task_name: string, pattern: string] {
  let store_path = $"(find_tools_cache_dir)/($task_name).task.input.txt"
  let previous_changeid = if ($store_path | path exists) {
    open $store_path
  } else {
    ""
  }
  let current_changeid = (compute_changeid $pattern)
  let is_same = ($previous_changeid == $current_changeid)
  {current_changeid: $current_changeid, previous_changeid: $previous_changeid, is_same: $is_same, store_path: $store_path}
}

def store_taskinput [task_input] {
  if not $task_input.is_same {
    mkdir ($task_input.store_path | path dirname)
    $task_input.current_changeid | save $task_input.store_path
  }
}

export def clean_taskinput [task_name_pattern: string] {
  glob $"(find_tools_cache_dir)/($task_name_pattern).task.input.txt" | each { |it|
    rm $it
    {action: "rm", path: $it}
  }
}

# def install_raw [folder: path] {
#   kubectl apply -f $folder
# }

# def uninstall_raw [folder: path] {
#   kubectl delete -f $folder
# }

export def detect_values_chart [cluster_name: string, chart_path: path] {
  let cluster_basename = ($cluster_name | parse '{base}-{env}' | get 0.base)
  (
    [ "" $"_($cluster_basename)" $"_($cluster_name)"] | each { |it|
      [$"($chart_path)/values($it).yaml", $"($chart_path)/../values($it).yaml"]

    }
    | flatten
    | where ($it | path exists)
  )
}

export def add_chart_repo [name: string, url: string] {
  install_helm
  if (helm repo list | from ssv --aligned-columns | where $it.NAME == $name | empty?) {
    do -i {
      helm repo add $name $url
      helm repo update $name
    } | complete
  }
}

export def debug_chart [cluster_name: string, chart_name: string, chart_namespace?: string] {
  install_helm

  let chart_install_name = $chart_name
  let chart_path = $chart_name
  let helm_opts = if $chart_namespace != null {
    ["--namespace" $chart_namespace "--create-namespace"]
  } else {
    []
  }
  let values = (detect_values_chart $cluster_name $chart_path | each {|$it| ["-f" $it] } | flatten)
  do -i { helm template $chart_install_name $chart_path $helm_opts --debug $values } | complete
}

export def lint_chart [cluster_name: string, chart_name: string] {
  install_helm

  let chart_path = $chart_name
  let values = (detect_values_chart $cluster_name $chart_path | each {|$it| ["-f" $it] } | flatten)
  do -i { helm lint $chart_path --strict $values } | complete
}

export def install_chart [cluster_name: string, chart_name: string, chart_namespace?: string] {
  install_helm

  let chart_install_name = $chart_name
  let chart_path = $chart_name
  if not ($chart_path | path exists) {
    echo $"not found: ($chart_path)"
  } else {
    let task_input = (make_taskinput $"install_chart_($chart_name)_($cluster_name)" $"($chart_path)/**")
    if $task_input.is_same {
      echo "noting to do"
    } else {
      let helm_opts = if $chart_namespace != null {
        ["--namespace" $chart_namespace "--create-namespace"]
      } else {
        []
      }
      let values = (detect_values_chart $cluster_name $chart_path | each {|$it| ["-f" $it] } | flatten)
      # print $"helm upgrade ($chart_install_name) ($chart_path) --install --cleanup-on-fail ($helm_opts) ($values)"
      let r = (do -i {
        helm dependency build $chart_path
        helm upgrade $chart_install_name $chart_path --install --cleanup-on-fail $helm_opts $values
      } | complete)
      if $r.exit_code == 0 {
        store_taskinput $task_input
        echo "done"
      } else {
        print $r
        echo "failed"
      }
    }
  }
}

export def uninstall_chart [chart_name: string, chart_namespace?: string] {
  install_helm

  let chart_install_name = $chart_name
  let helm_opts = if $chart_namespace != null {
    ["--namespace" $chart_namespace]
  } else {
    []
  }
  do -i { helm uninstall $chart_install_name $helm_opts } | complete
}

export def download_grafana_dashboards [folder: path] {
  # based on https://artifacthub.io/packages/helm/grafana/grafana?modal=template&template=configmap.yaml
  let dir = $"($folder)/grafana-dashboards"
  mkdir $dir
  open $"($folder)/values.yaml" | get dashboards | transpose key value | each --numbered { |it|
    let url = $"https://grafana.com/api/dashboards/($it.item.value.gnetId)/revisions/($it.item.value.revision  | default 1)/download"
    let content = (
      fetch -H ["Accept" "application/json"]
        -H ["Content-Type" "application/json;charset=UTF-8"]
        --raw
        $url
    )
    (
      $content
      | str replace '${DS_PROMETHEUS}' $it.item.value.datasource --all --string
      | str replace '[30s]' '[60s]' --all --string
      | save $"($dir)/($it.item.key).json" --raw
    )
    echo $url
  }
}

export def install_all_charts [] {
  find_chart_repos | each { |it| add_chart_repo $it.name $it.url }
  find_charts | each { |chart|
    {
      chart: $chart.name
      install_chart: (install_chart (find_current_cluster) $chart.name $chart.name)
    }
  }
}

export def uninstall_all_charts [] {
  find_charts | each { |chart|
    {
      chart: $chart.name
      uninstall_chart: (uninstall_chart $chart.name $chart.name)
    }
  }
}

export def annotates_resources [] {
  let annotations = ["sidecar.opentelemetry.io/inject=true", "linkerd.io/inject=enabled"]
  ["app" "grafana" "linkerd" "linkerd-viz" ] | each { |ns|
    kubectl annotate pods --all --overwrite -n $ns $annotations
    kubectl annotate namespace $ns --overwrite $annotations
  }
}

export def forward_ports [] {
  [
    ["svc" "ns" "cluster_port" "local_port"]
    ;
    ["gafana" "grafana" "80" "8040"]
    ["app" "app" "80" "8080"]
  ] | each { |it|
    kubectl port-forward -n $it.ns service/$it.svc $it.local_port:$it.cluster_port
  }
}
