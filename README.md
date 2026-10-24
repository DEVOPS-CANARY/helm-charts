# helm-charts

Platform Helm charts for DEVOPS-CANARY. Apps don't copy Kubernetes YAML: each
environment fills in a short values file in
[GitOps-Repo](https://github.com/DEVOPS-CANARY/GitOps-Repo), and Argo CD
renders it with a **pinned version** of a chart from this repo.

| Chart | For | Published as |
|---|---|---|
| [`rssb-app`](charts/rssb-app) | NestJS / Next.js products (backend + frontend + migrations + routing) | `oci://ghcr.io/devops-canary/charts/rssb-app` |

## Who owns what

| Repo | Owner | Contains |
|---|---|---|
| App repos | Developers | Code, Dockerfile, a short CI file. **No Kubernetes files.** |
| **helm-charts** (this repo) | Platform | *How* an app runs: probes, security, rollouts, routing |
| GitOps-Repo | Platform + CI bot | *What* runs where: values per app per environment, image digests, sealed secrets |

## How `rssb-app` builds a component

A product (e.g. logistics) is **one release per environment**, with each part
under `components`. Each component's settings are layered, and later wins:

```
componentDefaults  ->  typeDefaults.<nestjs|nextjs|worker>  ->  components.<name> (the values file)
```

**Types:** `nestjs` and `nextjs` serve HTTP (port, Service, probes, optionally a route).
`worker` is a background process, e.g. a Kafka consumer: no port, no Service, no route, no
HTTP probes, and a `command` (usually the backend image with a different entry point, so
it's built and scanned once). A worker must exit on a fatal error so Kubernetes restarts it.

**Autoscaling:** `autoscaling.metric: cpu` gives a plain HorizontalPodAutoscaler on CPU.
`metric: kafka` scales a Kafka consumer on its **lag** (messages waiting for its consumer
group) through KEDA, a platform component: the chart renders a `ScaledObject` and a
`TriggerAuthentication`. KEDA logs in to Kafka with the component's own `KAFKA_BROKERS`,
`KAFKA_USERNAME` and `KAFKA_PASSWORD`, read from its environment, so credentials are never
copied. Use it for workers whose CPU stays low while a backlog grows (they wait on email,
SMS or other services).

So a values file only lists what differs. See [`values.yaml`](charts/rssb-app/values.yaml)
for every option and its default, and GitOps-Repo `apps/logistics/envs/uat/values.yaml`
for a real example.

**Not configurable, on purpose:** the pod security settings (non-root, read-only
root filesystem, no privilege escalation, all capabilities dropped). They are
platform rules, required by the `restricted` Pod Security level on every namespace.

**Guard rails:** `values.schema.json` rejects bad values before anything is rendered:

- image tags instead of `sha256:` digests
- typos such as `replcas`
- unknown app types
- missing ports (except on a worker, which needs a `command` instead)
- scaling on Kafka without naming the topic and consumer group
- exposing a component that has no port
- invalid names

## Rules that keep the chart small

A shared chart is only worth it while anyone on the team can read it. So:

- **No option until two apps need it.** One app's special case is not a reason to add a
  setting that every reader of the chart has to understand.
- **Templates stay plain.** `if`, `range` and the helpers in `_helpers.tpl`; no new
  template logic when a default in `values.yaml` would do.
- **Platform rules are not options.** Security contexts and the selector label are fixed.
- **Owners review every chart PR.** Most of the team only ever edits values files in
  GitOps-Repo.

## Changing a chart

1. Edit the chart and **bump `version` in `Chart.yaml`**: patch for fixes, minor for new
   options, major for breaking changes. CI fails a PR that changes a chart without
   bumping it.
2. If you add an option, cover it in `ci/*.yaml`. CI renders every file in `ci/` and
   validates the output against the Kubernetes API schemas.
3. Merge. CI publishes the new version to GHCR. Published versions are never
   overwritten.
4. Roll it out like an image: bump `chart.version` in UAT's values file first, and in
   staging/prod only once UAT is happy.

Test locally (use Helm **v4.2.1**, the version Argo CD v3.5.5 renders with):

```sh
helm lint --strict charts/rssb-app -f charts/rssb-app/ci/overrides-values.yaml
helm template logistics charts/rssb-app -f ../GitOps-Repo/apps/logistics/envs/uat/values.yaml
```
