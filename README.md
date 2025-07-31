# *Frontend GitHub Scaffolding* Blueprint

This is a Blueprint used to scaffold a toolchain to host and deploy a fully functional frontend App (FireworksApp).

This Blueprint implements the following steps:
1. Create an empty Github repository (on github.com) - [link](https://github.com/krateoplatformops-blueprints/frontend-github-scaffolding-blueprint/blob/main/chart/templates/git-repo.yaml)
2. Push the code from the [skeleton](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/tree/main/skeleton) to the previously create repository - [link](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/blob/main/chart/templates/git-clone.yaml)
3. A Continuous Integration pipeline (GitHub [workflow](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/blob/main/skeleton/.github/workflows/ci.yml)) will build the Dockerfile of the frontend app and the resulting image will be published as a Docker image on the GitHub Package registry
4. An ArgoCD Application will be deployed to listen to the Helm Chart of the FireworksApp application and deploy the chart on the same Kubernetes cluster where ArgoCD is hosted
5. The FireworksApp will be deployed with a Service type of NodePort kind exposed on the chosen port.

## Requirements

- Install argo CLI: https://argo-cd.readthedocs.io/en/stable/cli_installation/
- Have Krateo PlatformOps >= 2.5.0 installed: https://docs.krateo.io/

### Setup toolchain on krateo-system namespace

```sh
helm repo add krateo https://charts.krateo.io
helm repo update krateo
helm install github-provider-kog krateo/github-provider-kog --namespace krateo-system --create-namespace --wait --version 0.0.7
helm install git-provider krateo/git-provider --namespace krateo-system --create-namespace --wait --version 0.10.1
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm install argocd argo/argo-cd --namespace krateo-system --create-namespace --wait --version 8.0.17
```

### Create a *krateo-account* user on ArgoCD

```sh
kubectl patch configmap argocd-cm -n krateo-system --patch '{"data": {"accounts.krateo-account": "apiKey, login"}}'
kubectl patch configmap argocd-rbac-cm -n krateo-system --patch '{"data": {"policy.default": "role:readonly"}}'
```

### Generate a token for *krateo-account* user

In order to generate a token, follow this instructions:

```sh
kubectl port-forward service/argocd-server -n krateo-system 8443:443
```

Open a new terminal and execute the following commands:

```sh
PASSWORD=$(kubectl -n krateo-system get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8443 --insecure --username admin --password $PASSWORD
argocd account list
TOKEN=$(argocd account generate-token --account krateo-account)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: argocd-endpoint
  namespace: krateo-system
stringData:
  insecure: "true"
  server-url: https://argocd-server.krateo-system.svc:443
  token: $TOKEN
EOF
```

### Generate a token for GitHub user

In order to generate a token, follow this instructions: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic

Give the following permissions: delete:packages, delete_repo, repo, workflow, write:packages

Substitute the <PAT> value with the generated token:

```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
stringData:
  token: <PAT>
kind: Secret
metadata:
  name: github-repo-creds
  namespace: krateo-system
type: Opaque
EOF
```

### Wait for GitHub Provider to be ready

```sh
until kubectl get deployment github-provider-kog-repo-controller -n krateo-system &>/dev/null; do
  echo "Waiting for Repo controller deployment to be created..."
  sleep 5
done
kubectl wait deployments github-provider-kog-repo-controller --for condition=Available=True --namespace krateo-system --timeout=300s

```

### Create a *fireworksapp-system* namespace

```sh
kubectl create ns fireworksapp-system
```

### Create a BearerAuth Custom Resource

Create a BearerAuth Custom Resource to make the GitHub Provider able to authenticate with the GitHub API using the previously created token.

```sh
cat <<EOF | kubectl apply -f -
apiVersion: github.kog.krateo.io/v1alpha1
kind: BearerAuth
metadata:
  name: bearer-github-ref
  namespace: fireworksapp-system
spec:
  tokenRef:
    key: token
    name: github-repo-creds
    namespace: krateo-system
EOF
```

## Usage

### Install the Helm Chart

Download Helm Chart values:

```sh
helm repo add marketplace https://marketplace.krateo.io
helm repo update marketplace
helm inspect values marketplace/frontend-github-scaffolding --version 0.0.1 > ~/frontend-github-scaffolding-values.yaml
```

Modify the *frontend-github-scaffolding-values.yaml* file as the following example:

```yaml
argocd:
  namespace: krateo-system
  application:
    project: default
    source:
      path: chart/
    destination:
      server: https://kubernetes.default.svc
      namespace: fireworks-app
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
app:
  service:
    type: NodePort
    port: 31180
git:
  unsupportedCapabilities: true
  deletionPolicy: Orphan
  insecure: true
  fromRepo:
    scmUrl: https://github.com
    org: krateoplatformops-blueprints
    name: frontend-github-scaffolding
    branch: main
    path: skeleton/
    credentials:
      authMethod: generic
      secretRef:
        namespace: krateo-system
        name: github-repo-creds
        key: token
  toRepo:
    scmUrl: https://github.com
    org: krateoplatformops-test
    name: fireworks-app
    branch: main
    path: /
    credentials:
      authMethod: generic
      secretRef:
        namespace: krateo-system
        name: github-repo-creds
        key: token
    private: false
    initialize: true
    deletionPolicy: Delete
    verbose: false
```

Install the Blueprint:

```sh
helm install <release-name> frontend-github-scaffolding \
  --repo https://marketplace.krateo.io \
  --namespace <release-namespace> \
  --create-namespace \
  -f ~/frontend-github-scaffolding-values.yaml
  --version 0.0.1 \
  --wait
```

### Install using Krateo Composable Operation

Install the CompositionDefinition for the *Blueprint*:

```sh
cat <<EOF | kubectl apply -f -
apiVersion: core.krateo.io/v1alpha1
kind: CompositionDefinition
metadata:
  name: frontend-github-scaffolding
  namespace: krateo-system
spec:
  chart:
    repo: frontend-github-scaffolding
    url: https://marketplace.krateo.io
    version: 0.0.1
EOF
```

Install the Blueprint using, as metadata.name, the *Composition* name (the Helm Chart name of the composition):

```sh
cat <<EOF | kubectl apply -f -
apiVersion: composition.krateo.io/v0-0-1
kind: FrontendGithubScaffolding
metadata:
  name: <release-name> 
  namespace: <release-namespace> 
spec:
  argocd:
    namespace: krateo-system
    application:
      project: default
      source:
        path: chart/
      destination:
        server: https://kubernetes.default.svc
        namespace: fireworks-app
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
  app:
    service:
      type: NodePort
      port: 31180
  git:
    unsupportedCapabilities: true
    insecure: true
    fromRepo:
      scmUrl: https://github.com
      org: krateoplatformops-blueprints
      name: frontend-github-scaffolding
      branch: main
      path: skeleton/
      credentials:
        authMethod: generic
        secretRef:
          namespace: krateo-system
          name: github-repo-creds
          key: token
    toRepo:
      scmUrl: https://github.com
      org: krateoplatformops-test
      name: fireworks-app
      branch: main
      path: /
      credentials:
        authMethod: generic
        secretRef:
          namespace: krateo-system
          name: github-repo-creds
          key: token
      private: false
      initialize: true
      deletionPolicy: Delete
      verbose: false
EOF
```