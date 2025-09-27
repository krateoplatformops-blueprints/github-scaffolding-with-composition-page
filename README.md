# *GitHub Scaffolding* Blueprint with Composition page

This is a Blueprint used to scaffold a toolchain to host and deploy a fully functional frontend App (FireworksApp).

This Blueprint implements the following steps:
1. Create an empty Github repository (on github.com) - [link](https://github.com/krateoplatformops-blueprints/github-scaffolding-with-composition-page/blob/main/chart/templates/git-repo.yaml)
2. Push the code from the [skeleton](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/tree/main/skeleton) to the previously create repository - [link](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/blob/main/chart/templates/git-clone.yaml)
3. A Continuous Integration pipeline (GitHub [workflow](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/blob/main/skeleton/.github/workflows/ci.yml)) will build the Dockerfile of the frontend app and the resulting image will be published as a Docker image on the GitHub Package registry
4. An ArgoCD Application will be deployed to listen to the Helm Chart of the FireworksApp application and deploy the chart on the same Kubernetes cluster where ArgoCD is hosted
5. The FireworksApp will be deployed with a Service type of NodePort kind exposed on the chosen port.
6. A composition page is available on Krateo Composable Portal

## Requirements

- Install argo CLI: https://argo-cd.readthedocs.io/en/stable/cli_installation/
- Have Krateo PlatformOps 2.6.0 installed: https://docs.krateo.io/

### Setup toolchain on krateo-system namespace

```sh
helm repo add marketplace https://marketplace.krateo.io
helm repo update marketplace
helm install github-provider-kog-repo marketplace/github-provider-kog-repo --namespace krateo-system --create-namespace --wait --version 1.0.0
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
kubectl wait restdefinitions.ogen.krateo.io github-provider-kog-repo --for condition=Ready=True --namespace krateo-system --timeout=300s
```

### Create a RepoConfiguration Custom Resource

Create a RepoConfiguration Custom Resource to make the GitHub Provider able to authenticate with the GitHub API using the previously created token.

```sh
cat <<EOF | kubectl apply -f -
apiVersion: github.ogen.krateo.io/v1alpha1
kind: RepoConfiguration
metadata:
  name: repo-config
  namespace: demo-system
spec:
  authentication:
    bearer:
      tokenRef:
        name: github-repo-creds
        namespace: krateo-system
        key: token
EOF
```

## Usage

### Install the Helm Chart

Download Helm Chart values:

```sh
helm repo add marketplace https://marketplace.krateo.io
helm repo update marketplace
helm inspect values marketplace/github-scaffolding-with-composition-page --version 1.1.0 > ~/github-scaffolding-with-composition-page-values.yaml
```

Modify the *github-scaffolding-with-composition-page-values.yaml* file as the following example:

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
    syncEnabled: false
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
    name: github-scaffolding-with-composition-page
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
    configurationRef:
      name: repo-config
      namespace: demo-system
```

Install the Blueprint:

```sh
helm install <release-name> github-scaffolding-with-composition-page \
  --repo https://marketplace.krateo.io \
  --namespace <release-namespace> \
  --create-namespace \
  -f ~/github-scaffolding-with-composition-page-values.yaml
  --version 1.1.0 \
  --wait
```

### Install using Krateo Composable Operation

Install the CompositionDefinition for the *Blueprint*:

```sh
cat <<EOF | kubectl apply -f -
apiVersion: core.krateo.io/v1alpha1
kind: CompositionDefinition
metadata:
  name: github-scaffolding-with-composition-page
  namespace: krateo-system
spec:
  chart:
    repo: github-scaffolding-with-composition-page
    url: https://marketplace.krateo.io
    version: 1.1.0
EOF
```

Install the Blueprint using, as metadata.name, the *Composition* name (the Helm Chart name of the composition):

```sh
cat <<EOF | kubectl apply -f -
apiVersion: composition.krateo.io/v1-1-0
kind: GithubScaffoldingWithCompositionPage
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
      syncEnabled: false
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
      name: github-scaffolding-with-composition-page
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
      configurationRef:
        name: repo-config
        namespace: demo-system
EOF
```

### Install using Krateo Composable Portal

```sh
cat <<EOF | kubectl apply -f -
apiVersion: core.krateo.io/v1alpha1
kind: CompositionDefinition
metadata:
  name: portal-blueprint-page
  namespace: krateo-system
spec:
  chart:
    repo: portal-blueprint-page
    url: https://marketplace.krateo.io
    version: 1.0.5
EOF
```

Install the Blueprint using, as metadata.name, the *Blueprint* name (the Helm Chart name of the blueprint):

```sh
cat <<EOF | kubectl apply -f -
apiVersion: composition.krateo.io/v1-0-5
kind: PortalBlueprintPage
metadata:
  name: github-scaffolding-with-composition-page
  namespace: demo-system
spec:
  blueprint:
    url: https://marketplace.krateo.io
    version: 1.1.0 # this is the Blueprint version
    hasPage: true
  form:
    alphabeticalOrder: false
  panel:
    title: GitHub Scaffolding with Composition Page
    icon:
      name: fa-cubes
EOF
```