# DagsHub Installation Makefile for OpenShift
# Requires: RHOAI v3.4+ with MLflow built-in
# Usage: make install-dagshub NAMESPACE=dagshub SERVICE_ACCOUNT=service-account.json [URL=https://my-dagshub.com]

.PHONY: help install-dagshub create-namespaces create-secrets check-service-account check-url authenticate-helm deploy-mlflow deploy-dagshub init-storage expose-route uninstall-dagshub delete-secrets clean status logs restart-main-pod deploy-workbench uninstall-workbench workbench-status mlflow-status uninstall-mlflow

# Default values
NAMESPACE ?= dagshub
LABEL_STUDIO_NAMESPACE ?= label-studio
SERVICE_ACCOUNT ?= service-account.json
URL ?= http://localhost:3000
CHART_VERSION ?= 1.26.7
RELEASE_NAME ?= dagshub
OCI_REGISTRY ?= oci://us-docker.pkg.dev/dagshub-containers/dagshub-charts/dagshub
FS_GROUP ?= 0

# MLflow integration variables
MLFLOW_RELEASE_NAME ?= dagshub-mlflow
MLFLOW_CHART_PATH ?= deploy/helm/mlflow
MLFLOW_TOKEN_SECRET_NAME ?= dagshub-mlflow-token
MLFLOW_PROXY_NAME ?= mlflow-workspace-proxy
MLFLOW_PROXY_PORT ?= 8080
MLFLOW_PROXY_URL ?= http://$(MLFLOW_PROXY_NAME).$(NAMESPACE).svc:$(MLFLOW_PROXY_PORT)

# Workbench specific variables
WORKBENCH_NAME ?= dagshub-llm-tutorial
WORKBENCH_NAMESPACE ?= $(NAMESPACE)
WORKBENCH_CHART_PATH ?= deploy/helm/workbench

# Conditionally set version flag (empty if CHART_VERSION is not set)
VERSION_FLAG = $(if $(CHART_VERSION),--version $(CHART_VERSION),)

# URL validation patterns
HTTPS_PREFIX := https://
URL_SUFFIX := .com

# Derived values (extracted during runtime, validated in check-service-account)
DOCKER_EMAIL = $(shell grep -o '"client_email": *"[^"]*"' $(SERVICE_ACCOUNT) 2>/dev/null | sed 's/"client_email": *"\([^"]*\)"/\1/')
NGINX_SERVICE = $(RELEASE_NAME)-nginx

# Color output
GREEN = \033[32m
YELLOW = \033[033m
RED = \033[031m
NC = \033[0m # No Color

help:
	@echo -e "$(GREEN)DagsHub OpenShift Installation Makefile$(NC)"
	@echo -e "$(YELLOW)Requires: RHOAI v3.4+ with MLflow built-in$(NC)"
	@echo ""
	@echo "Usage:"
	@echo "  make install-dagshub [NAMESPACE=<namespace>] [SERVICE_ACCOUNT=<path>] [URL=<url>]"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE                 - OpenShift namespace for DagsHub (default: dagshub)"
	@echo "  SERVICE_ACCOUNT           - Path to GCP service account JSON (default: service-account.json)"
	@echo "  URL                       - Public URL for DagsHub (default: http://localhost:3000)"
	@echo "                              For production, use HTTPS URL ending with .com"
	@echo "  LABEL_STUDIO_NAMESPACE    - Label Studio namespace (default: label-studio)"
	@echo "  CHART_VERSION             - Helm chart version (default: 1.26.7)"
	@echo "  RELEASE_NAME              - Helm release name (default: dagshub)"
	@echo "  FS_GROUP                  - Pod fsGroup for volume permissions (default: 0)"
	@echo "  MLFLOW_PROXY_URL          - MLflow workspace proxy URL (default: http://mlflow-workspace-proxy.<NAMESPACE>.svc:8080)"
	@echo ""
	@echo "Examples:"
	@echo ""
	@echo "  # Install with custom URL"
	@echo "  make install-dagshub NAMESPACE=<NAMESPACE> SERVICE_ACCOUNT=./sa.json URL=https://dagshub.example.com"
	@echo ""
	@echo "  # Check status"
	@echo "  make status NAMESPACE=<NAMESPACE>"
	@echo ""
	@echo "  # Uninstall"
	@echo "  make uninstall-dagshub NAMESPACE=<NAMESPACE>"
	@echo ""
	@echo "Workbench Commands:"
	@echo ""
	@echo "  # Deploy LLM Tutorial workbench"
	@echo "  make deploy-workbench NAMESPACE=<NAMESPACE> [URL=<dagshub_url>]"
	@echo ""
	@echo "  # Check workbench status"
	@echo "  make workbench-status NAMESPACE=<NAMESPACE>"
	@echo ""
	@echo "  # Uninstall workbench"
	@echo "  make uninstall-workbench NAMESPACE=<NAMESPACE>"
	@echo ""
	@echo "MLflow Commands:"
	@echo ""
	@echo "  # Check MLflow status"
	@echo "  make mlflow-status NAMESPACE=<NAMESPACE>"
	@echo ""
	@echo "  # Uninstall MLflow SA/RBAC integration"
	@echo "  make uninstall-mlflow NAMESPACE=<NAMESPACE>"
	@echo ""

check-service-account:
	@if [ ! -f "$(SERVICE_ACCOUNT)" ]; then \
		echo -e "$(RED)Error: Service account file '$(SERVICE_ACCOUNT)' not found$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)✓ Service account file found: $(SERVICE_ACCOUNT)$(NC)"
	@if [ -z "$(DOCKER_EMAIL)" ]; then \
		echo -e "$(RED)Error: Failed to extract client_email from service account file$(NC)"; \
		echo -e "$(RED)Please ensure the file is a valid GCP service account JSON$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)✓ Extracted client_email: $(DOCKER_EMAIL)$(NC)"

check-url:
	@echo -e "$(YELLOW)Validating URL...$(NC)"
	@if [ "$(URL)" != "http://localhost:3000" ]; then \
		if ! echo "$(URL)" | grep -q "^$(HTTPS_PREFIX)"; then \
			echo -e "$(RED)Error: Custom URL must start with https://$(NC)"; \
			echo -e "$(RED)Provided: $(URL)$(NC)"; \
			echo -e "$(YELLOW)For production use, provide a valid HTTPS URL: URL=https://dagshub.example.com$(NC)"; \
			exit 1; \
		fi; \
		if ! echo "$(URL)" | grep -q "$(URL_SUFFIX)$$"; then \
			echo -e "$(RED)Error: Custom URL must end with .com$(NC)"; \
			echo -e "$(RED)Provided: $(URL)$(NC)"; \
			exit 1; \
		fi; \
	fi
	@echo -e "$(GREEN)✓ URL validated: $(URL)$(NC)"

authenticate-helm: check-service-account
	@echo -e "$(YELLOW)Authenticating to Helm OCI registry...$(NC)"
	@cat $(SERVICE_ACCOUNT) | helm registry login -u _json_key --password-stdin us-docker.pkg.dev
	@echo -e "$(GREEN)✓ Helm registry authentication successful$(NC)"

create-namespaces:
	@echo -e  "$(YELLOW)Creating namespaces...$(NC)"
	@oc create namespace $(NAMESPACE) --dry-run=client -o yaml | oc apply -f -
	@oc create namespace $(LABEL_STUDIO_NAMESPACE) --dry-run=client -o yaml | oc apply -f -
	@echo -e "$(GREEN)✓ Namespaces created: $(NAMESPACE), $(LABEL_STUDIO_NAMESPACE)$(NC)"

create-secrets: check-service-account
	@echo -e "$(YELLOW)Creating container registry secrets...$(NC)"
	@oc create secret docker-registry container-registry \
		-n $(NAMESPACE) \
		--docker-server=gcr.io \
		--docker-username=_json_key \
		--docker-password="$$(cat $(SERVICE_ACCOUNT))" \
		--docker-email="$(DOCKER_EMAIL)" \
		--dry-run=client -o yaml | oc apply -f -
	@oc create secret docker-registry container-registry \
		-n $(LABEL_STUDIO_NAMESPACE) \
		--docker-server=gcr.io \
		--docker-username=_json_key \
		--docker-password="$$(cat $(SERVICE_ACCOUNT))" \
		--docker-email="$(DOCKER_EMAIL)" \
		--dry-run=client -o yaml | oc apply -f -
	@echo -e "$(GREEN)✓ Container registry secrets created$(NC)"
	@echo -e "$(YELLOW)Creating OCI registry secrets (for Helm chart pulls)...$(NC)"
	@oc create secret docker-registry oci-registry \
		-n $(NAMESPACE) \
		--docker-server=us-docker.pkg.dev \
		--docker-username=_json_key \
		--docker-password="$$(cat $(SERVICE_ACCOUNT))" \
		--docker-email="$(DOCKER_EMAIL)" \
		--dry-run=client -o yaml | oc apply -f -
	@oc create secret docker-registry oci-registry \
		-n $(LABEL_STUDIO_NAMESPACE) \
		--docker-server=us-docker.pkg.dev \
		--docker-username=_json_key \
		--docker-password="$$(cat $(SERVICE_ACCOUNT))" \
		--docker-email="$(DOCKER_EMAIL)" \
		--dry-run=client -o yaml | oc apply -f -
	@echo -e "$(GREEN)✓ OCI registry secrets created in both namespaces$(NC)"

deploy-mlflow:
	@echo -e "$(YELLOW)Setting up MLflow integration...$(NC)"
	@if ! oc get mlflow mlflow &>/dev/null; then \
		echo -e "$(RED)Error: MLflow CR 'mlflow' not found on the cluster$(NC)"; \
		echo -e "$(RED)RHOAI v3.4+ with MLflow is required. Please install it first.$(NC)"; \
		exit 1; \
	fi
	@if ! oc wait --for=condition=Available mlflow/mlflow --timeout=0 2>/dev/null; then \
		echo -e "$(RED)Error: MLflow instance is not yet available$(NC)"; \
		echo -e "$(YELLOW)Wait for it: oc wait --for=condition=Available mlflow/mlflow --timeout=120s$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)✓ MLflow is available on the cluster$(NC)"
	@echo -e "$(YELLOW)Creating service CA ConfigMap for MLflow TLS...$(NC)"
	@oc create configmap mlflow-service-ca \
		-n $(NAMESPACE) \
		--dry-run=client -o yaml | \
		oc apply -f -
	@oc annotate configmap mlflow-service-ca \
		-n $(NAMESPACE) \
		service.beta.openshift.io/inject-cabundle=true \
		--overwrite
	@echo -e "$(GREEN)✓ Service CA ConfigMap created$(NC)"
	@echo -e "$(YELLOW)Deploying MLflow SA/RBAC and workspace proxy...$(NC)"
	@MLFLOW_UI_URL=$$(oc get mlflow mlflow -o jsonpath='{.status.url}' 2>/dev/null); \
	helm upgrade --install $(MLFLOW_RELEASE_NAME) $(MLFLOW_CHART_PATH) \
		--namespace $(NAMESPACE) \
		$$([ -n "$$MLFLOW_UI_URL" ] && echo "--set workspaceProxy.mlflowUiUrl=$$MLFLOW_UI_URL") \
		--wait \
		--timeout 5m
	@echo -e "$(GREEN)✓ MLflow SA/RBAC and workspace proxy deployed$(NC)"
	@echo -e "$(YELLOW)Waiting for SA token to be populated...$(NC)"
	@TOKEN=""; \
	for i in 1 2 3 4 5; do \
		TOKEN=$$(oc get secret $(MLFLOW_TOKEN_SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.token}' 2>/dev/null); \
		if [ -n "$$TOKEN" ]; then break; fi; \
		sleep 2; \
	done; \
	if [ -n "$$TOKEN" ]; then \
		echo -e "$(GREEN)✓ SA token is ready$(NC)"; \
	else \
		echo -e "$(RED)Warning: SA token not yet populated$(NC)"; \
	fi

deploy-dagshub: check-url authenticate-helm
	@echo -e "$(YELLOW)Deploying DagsHub...$(NC)"
	@echo -e "$(YELLOW)Using URL: $(URL)$(NC)"
	@echo -e "$(YELLOW)Using chart version: $(CHART_VERSION)$(NC)"
	@echo -e "$(YELLOW)DagsHub will connect to MLflow via workspace proxy: $(MLFLOW_PROXY_URL)$(NC)"
	@helm upgrade --install $(RELEASE_NAME) $(OCI_REGISTRY) \
		$(VERSION_FLAG) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--set omitSecurityContextExceptFsGroup=true \
		--set rootUrl="$(URL)" \
		--set jwt.privateKey.defaultMode=0444 \
		--set gitServer.enabled=true \
		--set onboardStorage.bucket.endpointUrl=http://dagshub-seaweedfs-s3:8333 \
		--set labelstudio.namespaces.git=$(LABEL_STUDIO_NAMESPACE) \
		--set labelstudio.namespaces.dataEngine=$(LABEL_STUDIO_NAMESPACE) \
		--set temporal.server.securityContext=null \
		--set temporal.web.securityContext=null \
		--set temporal.server.podSecurityContext=null \
		--set temporal.web.podSecurityContext=null \
		--set redis.master.podSecurityContext.enabled=false \
		--set seaweedfs.master.podSecurityContext.enabled=false \
		--set seaweedfs.volume.podSecurityContext.enabled=false \
		--set seaweedfs.filer.podSecurityContext.enabled=false \
		--set mlflow.external.enabled=true \
		--set mlflow.external.url=$(MLFLOW_PROXY_URL) \
		--timeout 10m \
		--wait
	@echo -e "$(GREEN)✓ DagsHub deployed successfully$(NC)"

init-storage:
	@echo -e "$(YELLOW)Initializing SeaweedFS storage bucket...$(NC)"
	@echo -e "$(YELLOW)Waiting for SeaweedFS filer to be ready...$(NC)"
	@oc wait --for=condition=Ready pod/$(RELEASE_NAME)-seaweedfs-filer-0 -n $(NAMESPACE) --timeout=120s
	@EXISTING=$$(echo 's3.bucket.list' | oc exec -i -n $(NAMESPACE) $(RELEASE_NAME)-seaweedfs-filer-0 -- \
		weed shell -master $(RELEASE_NAME)-seaweedfs-master-0.$(RELEASE_NAME)-seaweedfs-master:9333 -filer localhost:8888 2>&1 | grep 'dagshub-storage' || true); \
	if [ -n "$$EXISTING" ]; then \
		echo -e "$(GREEN)✓ Bucket 'dagshub-storage' already exists$(NC)"; \
	else \
		echo 's3.bucket.create -name dagshub-storage' | oc exec -i -n $(NAMESPACE) $(RELEASE_NAME)-seaweedfs-filer-0 -- \
			weed shell -master $(RELEASE_NAME)-seaweedfs-master-0.$(RELEASE_NAME)-seaweedfs-master:9333 -filer localhost:8888 2>&1; \
		echo -e "$(GREEN)✓ Bucket 'dagshub-storage' created$(NC)"; \
	fi
	@echo -e "$(YELLOW)Restarting DagsHub pods to initialize S3 proxy...$(NC)"
	@oc rollout restart deployment $(RELEASE_NAME)-stateless-server -n $(NAMESPACE)
	@oc delete pod $(RELEASE_NAME)-0 -n $(NAMESPACE) --wait=false
	@oc rollout status deployment $(RELEASE_NAME)-stateless-server -n $(NAMESPACE) --timeout=120s
	@oc wait --for=condition=Ready pod/$(RELEASE_NAME)-0 -n $(NAMESPACE) --timeout=300s
	@echo -e "$(GREEN)✓ Storage initialized and DagsHub pods restarted$(NC)"

expose-route: check-url
	@if [ "$(URL)" = "http://localhost:3000" ]; then \
		echo -e "$(YELLOW)Skipping route creation (using localhost URL)$(NC)"; \
		echo -e "$(YELLOW)To access DagsHub, use port-forwarding:$(NC)"; \
		echo -e "$(YELLOW)  oc port-forward -n $(NAMESPACE) service/$(NGINX_SERVICE) 3000:80$(NC)"; \
	else \
		echo -e "$(YELLOW)Exposing nginx service via OpenShift route...$(NC)"; \
		URL_HOST=$$(echo "$(URL)" | sed -e 's|^https\?://||' -e 's|/.*||'); \
		if oc get route $(NGINX_SERVICE) -n $(NAMESPACE) &>/dev/null; then \
			echo -e "$(YELLOW)Route already exists$(NC)"; \
			ROUTE_URL=$$(oc get route $(NGINX_SERVICE) -n $(NAMESPACE) -o jsonpath='https://{.spec.host}'); \
			echo -e "$(GREEN)DagsHub is accessible at: $$ROUTE_URL$(NC)"; \
		else \
			oc create route edge $(NGINX_SERVICE) --service=$(NGINX_SERVICE) --hostname=$$URL_HOST -n $(NAMESPACE); \
			echo -e "$(GREEN)✓ Route created with hostname: $$URL_HOST and TLS$(NC)"; \
			echo -e "$(GREEN)DagsHub is accessible at: $(URL)$(NC)"; \
		fi; \
	fi

install-dagshub: check-service-account create-namespaces create-secrets deploy-mlflow deploy-dagshub init-storage expose-route
	@echo ""
	@echo -e "$(GREEN)========================================$(NC)"
	@echo -e "$(GREEN)DagsHub Installation Complete!$(NC)"
	@echo -e "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "To check pod status, run:"
	@echo "  oc get pods -n $(NAMESPACE)"
	@echo ""
	@echo "To view logs of the main pod, run:"
	@echo "  oc logs -f $(RELEASE_NAME)-0 -n $(NAMESPACE)"
	@echo ""

status:
	@echo -e "$(YELLOW)DagsHub Status in namespace: $(NAMESPACE)$(NC)"
	@echo ""
	@echo "Helm Release:"
	@helm list -n $(NAMESPACE) | grep $(RELEASE_NAME) || echo "No release found"
	@echo ""
	@echo "Pods:"
	@oc get pods -n $(NAMESPACE)
	@echo ""
	@echo "Services:"
	@oc get svc -n $(NAMESPACE) | grep $(RELEASE_NAME)
	@echo ""
	@if oc get route $(NGINX_SERVICE) -n $(NAMESPACE) &>/dev/null; then \
		echo "Route:"; \
		oc get route $(NGINX_SERVICE) -n $(NAMESPACE); \
		echo ""; \
		ROUTE_URL=$$(oc get route $(NGINX_SERVICE) -n $(NAMESPACE) -o jsonpath='https://{.spec.host}'); \
		echo -e "$(GREEN)Access DagsHub at: $$ROUTE_URL$(NC)"; \
	else \
		echo -e "$(YELLOW)No route exposed yet. Run 'make expose-route NAMESPACE=$(NAMESPACE)' to expose$(NC)"; \
	fi

delete-secrets:
	@echo -e "$(YELLOW)Deleting secrets from namespace: $(NAMESPACE)$(NC)"
	@oc delete secret container-registry -n $(NAMESPACE) --ignore-not-found=true
	@oc delete secret oci-registry -n $(NAMESPACE) --ignore-not-found=true
	@echo -e "$(GREEN)✓ Secrets deleted from $(NAMESPACE)$(NC)"
	@echo -e "$(YELLOW)Deleting secrets from namespace: $(LABEL_STUDIO_NAMESPACE)$(NC)"
	@oc delete secret container-registry -n $(LABEL_STUDIO_NAMESPACE) --ignore-not-found=true
	@oc delete secret oci-registry -n $(LABEL_STUDIO_NAMESPACE) --ignore-not-found=true
	@echo -e "$(GREEN)✓ Secrets deleted from $(LABEL_STUDIO_NAMESPACE)$(NC)"

uninstall-dagshub:
	@echo -e "$(RED)Uninstalling DagsHub from namespace: $(NAMESPACE)$(NC)"
	@helm uninstall $(RELEASE_NAME) -n $(NAMESPACE) || true
	@echo -e "$(YELLOW)Helm release uninstalled$(NC)"
	@oc delete route $(NGINX_SERVICE) -n $(NAMESPACE) --ignore-not-found=true
	@echo -e "$(YELLOW)Route deleted$(NC)"
	@$(MAKE) uninstall-mlflow NAMESPACE=$(NAMESPACE)
	@echo ""
	@read -p "Do you want to delete all PVCs in namespace '$(NAMESPACE)'? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		oc delete pvc --all -n $(NAMESPACE) --ignore-not-found=true; \
		echo -e "$(YELLOW)All PVCs deleted from $(NAMESPACE)$(NC)"; \
	else \
		echo -e "$(YELLOW)PVCs preserved. Run 'oc delete pvc --all -n $(NAMESPACE)' to delete them later$(NC)"; \
	fi
	@echo ""
	@read -p "Do you want to delete the secrets? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		$(MAKE) delete-secrets NAMESPACE=$(NAMESPACE) LABEL_STUDIO_NAMESPACE=$(LABEL_STUDIO_NAMESPACE); \
	else \
		echo -e "$(YELLOW)Secrets preserved. Run 'make delete-secrets NAMESPACE=$(NAMESPACE)' to delete them later$(NC)"; \
	fi
	@echo ""
	@read -p "Do you want to delete the namespace '$(NAMESPACE)'? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		oc delete namespace $(NAMESPACE) --wait=false; \
		echo -e "$(YELLOW)Namespace $(NAMESPACE) deletion initiated (this will also delete any remaining secrets)$(NC)"; \
	else \
		echo -e "$(YELLOW)Namespace $(NAMESPACE) preserved$(NC)"; \
	fi
	@echo ""
	@read -p "Do you want to delete the Label Studio namespace '$(LABEL_STUDIO_NAMESPACE)'? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		oc delete namespace $(LABEL_STUDIO_NAMESPACE) --wait=false; \
		echo -e "$(YELLOW)Namespace $(LABEL_STUDIO_NAMESPACE) deletion initiated (this will also delete any remaining secrets)$(NC)"; \
	else \
		echo -e "$(YELLOW)Namespace $(LABEL_STUDIO_NAMESPACE) preserved$(NC)"; \
	fi

clean: uninstall-dagshub
	@echo -e "$(GREEN)Cleanup complete$(NC)"

logs:
	@echo -e "$(YELLOW)Streaming logs from $(RELEASE_NAME)-0...$(NC)"
	@oc logs -f $(RELEASE_NAME)-0 -n $(NAMESPACE)

restart-main-pod:
	@echo -e "$(YELLOW)Restarting main DagsHub pod...$(NC)"
	@oc delete pod $(RELEASE_NAME)-0 -n $(NAMESPACE)
	@echo -e "$(GREEN)Pod deleted, waiting for restart...$(NC)"
	@oc wait --for=condition=Ready pod/$(RELEASE_NAME)-0 -n $(NAMESPACE) --timeout=300s
	@echo -e "$(GREEN)Pod restarted successfully$(NC)"

# Workbench deployment targets
deploy-workbench:
	@echo -e "$(GREEN)========================================$(NC)"
	@echo -e "$(GREEN)Deploying DagsHub LLM Tutorial Workbench$(NC)"
	@echo -e "$(GREEN)========================================$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Ensuring namespaces exist...$(NC)"
	@oc create namespace $(NAMESPACE) --dry-run=client -o yaml | oc apply -f -
	@echo -e "$(GREEN)✓ Namespace ready: $(NAMESPACE)$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Deploying workbench with Helm...$(NC)"
	@helm upgrade --install $(WORKBENCH_NAME) $(WORKBENCH_CHART_PATH) \
		--namespace $(NAMESPACE) \
		--set workbench.name="$(WORKBENCH_NAME)" \
		$(if $(URL),--set workbench.dagsHub.host="$(URL)",) \
		--wait \
		--timeout 10m
	@echo -e "$(GREEN)✓ Workbench deployed successfully$(NC)"
	@echo ""
	@echo -e "$(GREEN)========================================$(NC)"
	@echo -e "$(GREEN)Workbench Deployment Complete!$(NC)"
	@echo -e "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "To access the workbench:"
	@echo "1. Go to your OpenShift AI dashboard"
	@echo "2. Navigate to Data Science Projects"
	@echo "3. Find the '$(NAMESPACE)' project"
	@echo "4. Open the '$(WORKBENCH_NAME)-notebook' workbench"
	@echo ""
	@echo "The hello_world_llm.ipynb tutorial is already loaded in the workspace!"

workbench-status:
	@echo -e "$(YELLOW)DagsHub Workbench Status in namespace: $(NAMESPACE)$(NC)"
	@echo ""
	@echo "Helm Release:"
	@helm list -n $(NAMESPACE) | grep $(WORKBENCH_NAME) || echo "No workbench release found"
	@echo ""
	@echo "Notebooks:"
	@oc get notebook -n $(NAMESPACE) 2>/dev/null || echo "No notebooks found"
	@echo ""
	@echo "Pods:"
	@oc get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(WORKBENCH_NAME) 2>/dev/null || echo "No workbench pods found"
	@echo ""
	@echo "PVC:"
	@oc get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(WORKBENCH_NAME) 2>/dev/null || echo "No PVCs found"
	@echo ""
	@echo "Jobs:"
	@oc get jobs -n $(NAMESPACE) -l app.kubernetes.io/name=$(WORKBENCH_NAME) 2>/dev/null || echo "No jobs found"

uninstall-workbench:
	@echo -e "$(RED)Uninstalling DagsHub Workbench from namespace: $(NAMESPACE)$(NC)"
	@helm uninstall $(WORKBENCH_NAME) -n $(NAMESPACE) || true
	@echo -e "$(YELLOW)Helm release uninstalled$(NC)"
	@echo ""
	@read -p "Do you want to delete the workbench PVC (this will delete all notebook data)? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		oc delete pvc $(WORKBENCH_NAME)-notebook-pvc -n $(NAMESPACE) --ignore-not-found=true; \
		echo -e "$(YELLOW)PVC deleted$(NC)"; \
	else \
		echo -e "$(YELLOW)PVC preserved (you can delete it later with: oc delete pvc $(WORKBENCH_NAME)-notebook-pvc -n $(NAMESPACE))$(NC)"; \
	fi
	@echo -e "$(GREEN)Workbench uninstall complete$(NC)"

# MLflow status and cleanup targets
mlflow-status:
	@echo -e "$(YELLOW)MLflow Status$(NC)"
	@echo ""
	@echo "MLflow Instance (cluster-wide):"
	@oc get mlflows mlflow 2>/dev/null || echo "  No MLflow instance found"
	@echo ""
	@echo "MLflow URLs:"
	@INTERNAL=$$(oc get mlflow mlflow -o jsonpath='{.status.address.url}' 2>/dev/null); \
	EXTERNAL=$$(oc get mlflow mlflow -o jsonpath='{.status.url}' 2>/dev/null); \
	if [ -n "$$INTERNAL" ]; then \
		echo -e "  $(GREEN)Internal: $$INTERNAL$(NC)"; \
	else \
		echo -e "  $(YELLOW)Internal: not available$(NC)"; \
	fi; \
	if [ -n "$$EXTERNAL" ]; then \
		echo -e "  $(GREEN)External: $$EXTERNAL$(NC)"; \
	else \
		echo -e "  $(YELLOW)External: not configured$(NC)"; \
	fi
	@echo ""
	@echo "DagsHub Integration (namespace: $(NAMESPACE)):"
	@echo "  Helm Release:"
	@helm list -n $(NAMESPACE) 2>/dev/null | grep $(MLFLOW_RELEASE_NAME) || echo "    No MLflow release found"
	@echo "  ServiceAccount:"
	@oc get sa dagshub-mlflow-sa -n $(NAMESPACE) 2>/dev/null || echo "    No MLflow SA found"
	@echo "  Token Secret:"
	@if oc get secret $(MLFLOW_TOKEN_SECRET_NAME) -n $(NAMESPACE) -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; then \
		echo -e "    $(GREEN)$(MLFLOW_TOKEN_SECRET_NAME): token populated$(NC)"; \
	else \
		echo -e "    $(YELLOW)$(MLFLOW_TOKEN_SECRET_NAME): not found or empty$(NC)"; \
	fi
	@echo "  ClusterRoleBindings:"
	@oc get clusterrolebinding dagshub-mlflow-edit-$(NAMESPACE) dagshub-mlflow-view-$(NAMESPACE) dagshub-mlflow-integration-$(NAMESPACE) 2>/dev/null || echo "    No ClusterRoleBindings found"

uninstall-mlflow:
	@echo -e "$(RED)Uninstalling MLflow integration$(NC)"
	@helm uninstall $(MLFLOW_RELEASE_NAME) -n $(NAMESPACE) 2>/dev/null || true
	@oc delete clusterrolebinding dagshub-mlflow-edit-$(NAMESPACE) dagshub-mlflow-view-$(NAMESPACE) dagshub-mlflow-integration-$(NAMESPACE) --ignore-not-found=true 2>/dev/null || true
	@oc delete configmap mlflow-service-ca -n $(NAMESPACE) --ignore-not-found=true 2>/dev/null || true
	@echo -e "$(GREEN)✓ MLflow Helm release and RBAC removed from namespace $(NAMESPACE)$(NC)"
	@echo ""
	@echo -e "$(YELLOW)NOTE: The cluster-wide MLflow instance was not removed.$(NC)"
	@echo -e "$(YELLOW)To remove it: oc delete mlflow mlflow$(NC)"
