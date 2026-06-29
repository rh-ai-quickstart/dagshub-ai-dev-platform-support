# Deploy DagsHub LLM Tutorial Workbench

Learn LLM development with hands-on tutorials covering RAG, fine-tuning, and evaluation in a pre-configured Jupyter environment on OpenShift AI.

## Table of contents

- [Detailed description](#detailed-description)
- [Architecture diagrams](#architecture-diagrams)
- [Requirements](#requirements)
- [Deploy](#deploy)
- [Delete](#delete)
- [Tags](#tags)

## Detailed description

This quickstart deploys a comprehensive LLM development environment that teaches practitioners how to build, fine-tune, and evaluate large language models using DagsHub's MLOps platform. The workbench provides a hands-on tutorial covering the complete machine learning lifecycle for LLM applications.

The solution addresses the common challenge of learning LLM development without access to proper tooling and examples. Instead of struggling with complex setup procedures, data scientists and ML engineers can immediately start working with a fully configured environment that demonstrates best practices for LLM workflows.

The tutorial covers essential LLM development concepts including Retrieval-Augmented Generation (RAG) pipeline construction, model fine-tuning with LoRA adapters, and comprehensive evaluation strategies using RAGAS and LLM-as-a-judge techniques. This hands-on approach accelerates learning and provides practical experience with production-ready MLOps tools.


## Requirements

- OpenShift cluster with OpenShift AI operator installed and configured
- Cluster admin privileges for workbench deployment
- Helm 3.8+ installed and configured
- `oc` CLI tool authenticated to the target cluster
- Network access to external git repositories for documentation fetching

### Minimum hardware requirements

- 2 vCPU cores allocated to the workbench
- 4 GB RAM allocated to the workbench  
- 20 GB persistent storage for workspace data
- GPU access recommended for model fine-tuning exercises

### Minimum software requirements

- Red Hat OpenShift 4.12+
- Red Hat OpenShift AI 3.4+
- Helm 3.8+
- OpenShift CLI (`oc`) 4.12+

## Deploy

**Note:** This workbench uses the project's Makefile for simplified deployment and management. All commands should be run from the project root directory.

1. Navigate to the project root directory:
   ```bash
   cd /path/to/dagshub-ai-dev-platform-support
   ```

2. Deploy the workbench using the Makefile:
   ```bash
   make deploy-workbench NAMESPACE=<namespace> URL=https://your-company-dagshub.com
   ```

3. Monitor the deployment progress:
   ```bash
   oc get pods -n <namespace> -w
   ```

4. Access the workbench:
   - Open the OpenShift AI dashboard
   - Navigate to "Data Science Projects" 
   - Find your namespace/project
   - Click on the "dagshub-llm-tutorial-notebook" workbench
   - Open `hello_world_llm.ipynb` to start the tutorial

5. Verify the setup (check the workspace-setup initContainer logs):
   ```bash
   oc logs -n <namespace> -l app=dagshub-llm-tutorial-notebook -c workspace-setup
   ```

6. Check workbench status:
   ```bash
   make workbench-status NAMESPACE=<namespace>
   ```

### Available Makefile Commands

For a complete list of available commands and their usage, run:
```bash
make help
```

Key workbench commands:
- `make deploy-workbench NAMESPACE=<namespace> URL=<dagshub-url>` - Deploy the workbench
- `make workbench-status NAMESPACE=<namespace>` - Check workbench status
- `make uninstall-workbench NAMESPACE=<namespace>` - Remove the workbench

### Delete

Remove the workbench deployment using the Makefile:

```bash
make uninstall-workbench NAMESPACE=<namespace>
```

The Makefile will prompt you to confirm deletion of the PVC (persistent volume claim) containing notebook data. Choose 'y' to delete all data or 'N' to preserve it for future use.

## Tags

- **Industry**: Technology
- **Use case**: LLM development and training
- **Framework**: DagsHub, Jupyter, MLOps
- **Complexity**: Intermediate
- **Audience**: Data scientists, ML engineers
- **Technology**: Large Language Models, RAG, Fine-tuning, Model evaluation