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
helm inspect values marketplace/github-scaffolding-with-composition-page --version 1.2.0 > ~/github-scaffolding-with-composition-page-values.yaml
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
  --version 1.2.0 \
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
    version: 1.2.0
EOF
```

Install the Blueprint using, as metadata.name, the *Composition* name (the Helm Chart name of the composition):

```sh
cat <<EOF | kubectl apply -f -
apiVersion: composition.krateo.io/v1-2-0
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
apiVersion: composition.krateo.io/v1-1-0
kind: PortalBlueprintPage
metadata:
  name: github-scaffolding-with-composition-page
  namespace: demo-system
spec:
  blueprint:
    repo: github-scaffolding-with-composition-page
    url: https://marketplace.krateo.io
    version: 1.3.0
    hasPage: true
    credentials: {}
  form:
    widgetData:
      schema: {}
      objectFields: []
      submitActionId: submit-action-from-string-schema
      actions:
        rest:
          - id: submit-action-from-string-schema
            onEventNavigateTo:
              eventReason: "CompositionCreated"
              url: '${ "/compositions/" + .response.metadata.namespace + "/" + (.response.kind | ascii_downcase) + "/" + .response.metadata.name }'
              urlIfNoPage: "/blueprints"
              timeout: 50
            successMessage: '${"Successfully deployed " + .response.metadata.name + " composition in namespace " + .response.metadata.namespace }'
            resourceRefId: composition-to-post
            type: rest
            payloadToOverride:
              - name: spec
                value: ${ .json | del(.composition) }
              - name: metadata.name
                value: ${ .json.composition.name }
              - name: metadata.namespace
                value: ${ .json.composition.namespace }
            headers:
              - "Content-Type: application/json"
    widgetDataTemplate:
      - forPath: stringSchema
        expression: >
          ${
            .getNotOrderedSchema["values.schema.json"] as $schema
            | .allowedNamespaces[] as $allowedNamespaces

            # --- inject "composition" under top-level "properties" ---
            | "\"properties\": " | length as $keylen
            | ($schema | index("\"properties\": ")) as $idx
            | ($schema[0:$idx + $keylen]) as $prefix
            | ($schema[$idx + $keylen:]) as $rest
            | {
                composition: {
                  type: "object",
                  properties: {
                    name: {
                      type: "string"
                    },
                    namespace: {
                      type: "string",
                      enum: $allowedNamespaces
                    }
                  },
                  required: ["name", "namespace"]
                }
              } | tostring as $injected
            | ($prefix + $injected[:-1] + "," + $rest[1:]) as $withComposition

            # --- ensure top-level "required" includes "composition" ---
            | (
                if ($withComposition | test("\n  \"required\": \\[")) then
                  if ($withComposition | test("\n  \"required\": \\[[^\\]]*\"composition\"")) then
                    # "composition" already present at top-level
                    $withComposition
                  else
                    # prepend "composition" to existing top-level required array
                    ($withComposition
                    | gsub("\n  \"required\": \\["; "\n  \"required\": [\"composition\", "))
                  end
                else
                  # no top-level required: insert before top-level "type": "object"
                  ($withComposition | index("\n  \"type\": \"object\"")) as $tidx
                  | ($withComposition[0:$tidx+1]) as $p2
                  | ($withComposition[$tidx+1:]) as $r2
                  | $p2 + "  \"required\": [\"composition\"],\n" + $r2
                end
              )
          }
    resourcesRefsTemplate:
      iterator: ${ .allowedNamespacesWithResource[] }
      template:
        id: composition-to-post
        apiVersion: composition.krateo.io/v1-1-0
        namespace: ${ .namespace }
        resource: ${ .resource }
        verb: POST
    apiRef:
      name: '{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-restaction-schema-override-allows-ns'
      namespace: ""
    hasPage: false
    instructions: |
      # *GitHub Scaffolding* Blueprint with Composition page

      This is a Blueprint used to scaffold a toolchain to host and deploy a fully functional frontend App (FireworksApp).

      This Blueprint implements the following steps:
      1. Create an empty Github repository (on github.com) - [link](https://github.com/krateoplatformops-blueprints/github-scaffolding-with-composition-page/blob/main/chart/templates/git-repo.yaml)
      2. Push the code from the [skeleton](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/tree/main/skeleton) to the previously create repository - [link](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/blob/main/chart/templates/git-clone.yaml)
      3. A Continuous Integration pipeline (GitHub [workflow](https://github.com/krateoplatformops/krateo-v2-template-fireworksapp/blob/main/skeleton/.github/workflows/ci.yml)) will build the Dockerfile of the frontend app and the resulting image will be published as a Docker image on the GitHub Package registry
      4. An ArgoCD Application will be deployed to listen to the Helm Chart of the FireworksApp application and deploy the chart on the same Kubernetes cluster where ArgoCD is hosted
      5. The FireworksApp will be deployed with a Service type of NodePort kind exposed on the chosen port.
      6. A composition page is available on Krateo Composable Portal

  panel:
    markdown: Click here to deploy a **{{ .Release.Name }}** composition
    apiRef:
      name: "{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-restaction-compositiondefinition-schema-ns"
      namespace: ""
    widgetData:
      clickActionId: blueprint-click-action
      footer:
        - resourceRefId: blueprint-panel-button
      tags:
        - '{{ .Release.Namespace }}'
        - '{{ .Values.blueprint.version }}'
      icon:
        name: fa-cubes
      items:
        - resourceRefId: blueprint-panel-markdown
      title: GitHub Scaffolding with Composition Page
      actions:
        openDrawer:
          - id: blueprint-click-action
            resourceRefId: blueprint-form
            type: openDrawer
            size: large
        navigate:
          - id: blueprint-click-action
            path: '/{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-blueprint'
            type: navigate
    widgetDataTemplate:
      - forPath: icon.color
        expression: >
          ${
            (
              (
                .getCompositionDefinition?.status?.conditions // []
              )
              | map(
                  select(.type == "Ready")
                  | if .status == "False" then
                      "orange"
                    elif .status == "True" then
                      "green"
                    else
                      "grey"
                    end
                )
              | first
            )
            // "grey"
          }
      - forPath: headerLeft
        expression: >
          ${
            (
              (
                .getCompositionDefinition?.status?.conditions // []
              )
              | map(
                  select(.type == "Ready")
                  | if .status == "False" then
                      "Ready:False"
                    elif .status == "True" then
                      "Ready:True"
                    else
                      "Ready:Unknown"
                    end
                )
              | first
            )
            // "Ready:Unknown"
          }
      - forPath: headerRight
        expression: >
          ${
            .getCompositionDefinition // {}
            | .metadata.creationTimestamp
            // "In the process of being created"
          }
    resourcesRefs:
      items:
        - id: blueprint-panel-markdown
          apiVersion: widgets.templates.krateo.io/v1beta1
          name: '{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-panel-markdown'
          namespace: ''
          resource: markdowns
          verb: GET
        - id: blueprint-panel-button
          apiVersion: widgets.templates.krateo.io/v1beta1
          name: '{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-panel-button-cleanup'
          namespace: ''
          resource: buttons
          verb: DELETE
        - id: blueprint-form
          apiVersion: widgets.templates.krateo.io/v1beta1
          name: '{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-form'
          namespace: ''
          resource: forms
          verb: GET

  restActions:
    - name: '{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-restaction-compositiondefinition-schema-ns'
      namespace: ""
      api:
        - name: getCompositionDefinition
          path: "/apis/core.krateo.io/v1alpha1/namespaces/{{ .Release.Namespace }}/compositiondefinitions/{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}"
          verb: GET
          headers:
            - "Accept: application/json"
        - name: getCompositionDefinitionResource
          path: "/apis/core.krateo.io/v1alpha1/namespaces/{{ .Release.Namespace }}/compositiondefinitions/{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}"
          verb: GET
          headers:
            - "Accept: application/json"
          filter: ".getCompositionDefinitionResource.status.resource"
        - name: getOrderedSchema
          path: >
            ${ "/apis/apiextensions.k8s.io/v1/customresourcedefinitions/" + (.getCompositionDefinitionResource) + ".composition.krateo.io" }
          verb: GET
          headers:
            - "Accept: application/json"
          dependsOn:
            name: getCompositionDefinitionResource
          filter: >
            .getOrderedSchema.spec.versions[]
            | select(.name == "v{{ .Values.blueprint.version | replace "." "-" }}")
            | .schema.openAPIV3Schema.properties.spec
        - name: getNotOrderedSchema
          path: >
            ${ "/api/v1/namespaces/{{ .Release.Namespace }}/configmaps/" + (.getCompositionDefinitionResource) + "-v{{ .Values.blueprint.version | replace "." "-" }}-jsonschema-configmap" }
          verb: GET
          headers:
            - "Accept: application/json"
          dependsOn:
            name: getCompositionDefinitionResource
          filter: ".getNotOrderedSchema.data"
        - name: getNamespaces
          path: "/api/v1/namespaces"
          verb: GET
          headers:
            - "Accept: application/json"
          filter: "[.getNamespaces.items[] | .metadata.name]"
      filter: >
        {
          getOrderedSchema: .getOrderedSchema,
          getNotOrderedSchema: .getNotOrderedSchema,
          getCompositionDefinition: .getCompositionDefinition,
          getCompositionDefinitionResource: .getCompositionDefinitionResource,
          possibleNamespacesForComposition:
          [
            .getNamespaces[] as $ns |
            {
              resource: .getCompositionDefinitionResource,
              namespace: $ns
            }
          ]
        }

    - name: '{{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-restaction-schema-override-allows-ns'
      namespace: ""
      api:
        - name: getCompositionDefinitionSchemaNs
          path: "/call?apiVersion=templates.krateo.io/v1&resource=restactions&name={{ .Values.global.compositionKind | lower }}-{{ .Values.global.compositionName }}-restaction-compositiondefinition-schema-ns&namespace={{ .Release.Namespace }}"
          verb: GET
          endpointRef:
            name: snowplow-endpoint
            namespace: '{{ default "krateo-system" (default dict .Values.global).krateoNamespace }}'
          headers:
            - "Accept: application/json"
          continueOnError: true
          errorKey: getCompositionDefinitionSchemaNs
          exportJwt: true
        - name: allowedNamespaces
          continueOnError: true
          dependsOn:
            name: getCompositionDefinitionSchemaNs
            iterator: .getCompositionDefinitionSchemaNs.status.possibleNamespacesForComposition
          path: "/apis/authorization.k8s.io/v1/selfsubjectaccessreviews"
          verb: POST
          headers:
            - "Content-Type: application/json"
          payload: |
            ${
              {
                "kind": "SelfSubjectAccessReview",
                "apiVersion": "authorization.k8s.io/v1",
                "spec": {
                  "resourceAttributes": {
                    "namespace": .namespace,
                    "verb": "create",
                    "group": "composition.krateo.io",
                    "version": "v{{ .Values.blueprint.version | replace "." "-" }}",
                    "resource": .resource
                  }
                }
              }
            }
      filter: >
        {
          getOrderedSchema: .getCompositionDefinitionSchemaNs.status.getOrderedSchema,
          getNotOrderedSchema: .getCompositionDefinitionSchemaNs.status.getNotOrderedSchema,
          getCompositionDefinitionResource: .getCompositionDefinitionSchemaNs.status.getCompositionDefinitionResource,      
          allowedNamespaces: [
            [.allowedNamespaces[] | .status.allowed] as $allowed
            | [.getCompositionDefinitionSchemaNs.status.possibleNamespacesForComposition[] | .namespace]
            | to_entries
            | map(select($allowed[.key] == true) | .value)
          ],
          allowedNamespacesWithResource: [
            [.allowedNamespaces[] | .status.allowed] as $allowed
            | .getCompositionDefinitionSchemaNs.status.getCompositionDefinitionResource as $resource
            | [.getCompositionDefinitionSchemaNs.status.possibleNamespacesForComposition[] | .namespace]
            | to_entries
            | map(
                select($allowed[.key] == true)
                | {
                    namespace: .value,
                    resource: $resource
                  }
              )
          ]
        }




EOF
```