
data "google_client_config" "default" {
}

terraform {
  required_version = ">= 0.13"
  required_providers {
    google = {
      source  = "hashicorp/google-beta"
      version = ">= 4.30"
    }
  }
}

locals {
  prefix = var.name-prefix == "" ? "${var.neg-name}-" : var.name-prefix
}

module "backend" {
  count                 = "" != var.lb-scheme ? 1 : 0
  source                = (
    "github.com/TyeMcQueen/terraform-google-backend-to-gke" )
  cluster-objects       = var.cluster-objects
  clusters              = var.clusters
  description           = var.description
  health-interval-secs  = var.health-interval-secs
  health-path           = var.health-path
  health-ref            = var.health-ref
  health-timeout-secs   = var.health-timeout-secs
  healthy-threshold     = var.healthy-threshold
  lb-scheme             = var.lb-scheme
  log-sample-rate       = var.log-sample-rate
  max-rps-per           = var.max-rps-per
  name-prefix           = local.prefix
  neg-name              = var.neg-name
  project               = var.project
  unhealthy-threshold   = var.unhealthy-threshold
}

module "ingress" {
  source                = (
    "github.com/TyeMcQueen/terraform-google-http-ingress" )
  backend-ref           = (
    0 < length(module.backend) ? module.backend[0].backend.id : "" )
  bad-host-backend      = var.bad-host-backend
  bad-host-code         = var.bad-host-code
  bad-host-host         = var.bad-host-host
  bad-host-path         = var.bad-host-path
  bad-host-redir        = var.bad-host-redir
  cert-map-ref          = var.cert-map-ref
  create-lb-certs       = var.create-lb-certs
  description           = var.description
  dns-add-hosts         = var.dns-add-hosts
  dns-ttl-secs          = var.dns-ttl-secs
  dns-zone-ref          = var.dns-zone-ref
  hostnames             = var.hostnames
  http-redir-code       = var.http-redir-code
  ip-addr-ref           = var.ip-addr-ref
  ip-is-shared          = var.ip-is-shared
  labels                = var.labels
  lb-cert-refs          = var.lb-cert-refs
  lb-scheme             = var.lb-scheme
  map-cert-ids          = var.map-cert-ids
  map-name              = var.map-name
  name-prefix           = local.prefix
  project               = var.project
  quic-override         = var.quic-override
  redirect-http         = var.redirect-http
  reject-honeypot       = var.reject-honeypot
  url-map-ref           = var.url-map-ref
}
