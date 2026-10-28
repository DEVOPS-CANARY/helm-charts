# CRD schemas for CI

JSON schemas kubeconform validates rendered manifests against, for kinds the
[datree CRDs-catalog](https://github.com/datreeio/CRDs-catalog) does not carry yet
(provider-kafka 1.4.2). Generated from the provider's CRDs: the version's
`openAPIV3Schema` with a `$schema` line, named `<group>/<kind>_<version>.json`.
