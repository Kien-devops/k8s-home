param(
    [ValidateSet("all","workloads","platform","argocd")]
    [string]$Target = "all",
    [ValidateSet("png","svg","drawio","pdf")]
    [string]$Format = "png"
)

$GRAPHVIZ_PATH = "C:\Program Files\Graphviz\bin"
$KUBE_DIAGRAMS = "C:\Users\pc\AppData\Local\Programs\Python\Python312\Scripts\kube-diagrams"
$PROJECT_ROOT  = Split-Path -Parent $PSScriptRoot
$DEPLOY_DIR    = Join-Path $PROJECT_ROOT "deploy"
$OUTPUT_DIR    = Join-Path $PROJECT_ROOT "diagrams"

$env:PATH += ";$GRAPHVIZ_PATH"

if (-not (Test-Path $KUBE_DIAGRAMS)) { Write-Error "kube-diagrams not found. Run: pip install KubeDiagrams"; exit 1 }
if (-not (Get-Command dot -ErrorAction SilentlyContinue)) { Write-Error "Graphviz not found."; exit 1 }

New-Item -ItemType Directory -Force -Path $OUTPUT_DIR | Out-Null

function Generate-Diagram {
    param([string]$Label, [string]$Dir, [string]$OutFile)
    if (-not (Test-Path $Dir)) { Write-Warning "  DIR NOT FOUND: $Dir"; return }
    $files = Get-ChildItem -Path $Dir -Recurse -Filter "*.yaml" |
        Where-Object { $_.Name -ne "kustomization.yaml" } |
        ForEach-Object { $_.FullName }
    if ($files.Count -eq 0) { Write-Warning "  [$Label] No YAML files found - skipping."; return }
    Write-Host "  [$Label] $($files.Count) files..." -ForegroundColor Yellow
    python $KUBE_DIAGRAMS @files -o $OutFile -f $Format 2>&1 |
        Where-Object { $_ -match "\[Error\]|\[Warning\]|generated\." } |
        ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    if (Test-Path $OutFile) { Write-Host "    OK: $(Split-Path $OutFile -Leaf)" -ForegroundColor Green }
}

$tasks = @()
switch ($Target) {
    "workloads" {
        $tasks += @{Label="Backend (base)";  Dir="$DEPLOY_DIR\workloads\hospital-backend\base";          Out="workloads-backend-base"}
        $tasks += @{Label="Backend (prod)";  Dir="$DEPLOY_DIR\workloads\hospital-backend\overlays\prod"; Out="workloads-backend-prod"}
        $tasks += @{Label="Frontend (base)"; Dir="$DEPLOY_DIR\workloads\hospital-frontend\base";         Out="workloads-frontend-base"}
        $tasks += @{Label="Frontend (prod)"; Dir="$DEPLOY_DIR\workloads\hospital-frontend\overlays\prod";Out="workloads-frontend-prod"}
    }
    "platform" {
        $tasks += @{Label="Ingress/Traefik";   Dir="$DEPLOY_DIR\platform\ingress";                        Out="platform-ingress"}
        $tasks += @{Label="Monitoring";        Dir="$DEPLOY_DIR\platform\observability\monitoring";       Out="platform-monitoring"}
        $tasks += @{Label="Logging";           Dir="$DEPLOY_DIR\platform\observability\logging";          Out="platform-logging"}
        $tasks += @{Label="Security/Kyverno";  Dir="$DEPLOY_DIR\platform\security";                       Out="platform-security"}
        $tasks += @{Label="Redis Cache";       Dir="$DEPLOY_DIR\platform\caching";                        Out="platform-redis"}
        $tasks += @{Label="Namespaces";        Dir="$DEPLOY_DIR\platform\namespaces";                     Out="platform-namespaces"}
    }
    "argocd" {
        $tasks += @{Label="ArgoCD Apps";       Dir="$DEPLOY_DIR\argocd\applications";                    Out="argocd-applications"}
        $tasks += @{Label="ArgoCD Projects";   Dir="$DEPLOY_DIR\argocd\projects";                        Out="argocd-projects"}
        $tasks += @{Label="ArgoCD Bootstrap";  Dir="$DEPLOY_DIR\argocd\bootstrap";                       Out="argocd-bootstrap"}
    }
    default {
        $tasks += @{Label="Backend (base)";    Dir="$DEPLOY_DIR\workloads\hospital-backend\base";         Out="workloads-backend-base"}
        $tasks += @{Label="Backend (prod)";    Dir="$DEPLOY_DIR\workloads\hospital-backend\overlays\prod";Out="workloads-backend-prod"}
        $tasks += @{Label="Frontend (base)";   Dir="$DEPLOY_DIR\workloads\hospital-frontend\base";        Out="workloads-frontend-base"}
        $tasks += @{Label="Frontend (prod)";   Dir="$DEPLOY_DIR\workloads\hospital-frontend\overlays\prod";Out="workloads-frontend-prod"}
        $tasks += @{Label="Ingress/Traefik";   Dir="$DEPLOY_DIR\platform\ingress";                        Out="platform-ingress"}
        $tasks += @{Label="Monitoring";        Dir="$DEPLOY_DIR\platform\observability\monitoring";       Out="platform-monitoring"}
        $tasks += @{Label="Logging";           Dir="$DEPLOY_DIR\platform\observability\logging";          Out="platform-logging"}
        $tasks += @{Label="Security/Kyverno";  Dir="$DEPLOY_DIR\platform\security";                       Out="platform-security"}
        $tasks += @{Label="Redis Cache";       Dir="$DEPLOY_DIR\platform\caching";                        Out="platform-redis"}
        $tasks += @{Label="ArgoCD Apps";       Dir="$DEPLOY_DIR\argocd\applications";                    Out="argocd-applications"}
        $tasks += @{Label="ArgoCD Projects";   Dir="$DEPLOY_DIR\argocd\projects";                        Out="argocd-projects"}
        $tasks += @{Label="ArgoCD Bootstrap";  Dir="$DEPLOY_DIR\argocd\bootstrap";                       Out="argocd-bootstrap"}
    }
}

Write-Host ""
Write-Host "KubeDiagrams - Generating $($tasks.Count) diagram(s) [format=$Format]" -ForegroundColor Cyan
Write-Host "Output: $OUTPUT_DIR" -ForegroundColor Cyan
Write-Host ("-" * 55)

$generated = @()
foreach ($t in $tasks) {
    $outFile = Join-Path $OUTPUT_DIR "$($t.Out).$Format"
    Generate-Diagram -Label $t.Label -Dir $t.Dir -OutFile $outFile
    if (Test-Path $outFile) { $generated += $outFile }
}

Write-Host ("-" * 55)
Write-Host "Done! $($generated.Count)/$($tasks.Count) diagrams generated." -ForegroundColor Green
Write-Host ""
Start-Process explorer.exe $OUTPUT_DIR