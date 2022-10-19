
output "be" {
    description = "All outputs from the backend-to-gke module invocation"
    value       = module.backend
}

output "lb" {
    description = "All outputs from the http-ingress module invocation"
    value       = module.ingress
}

output "backend" {
  description = "A 0- or 1-entry list of Backend Service resource created"
  value       = [ for be in module.backend : be.backend ]
}

output "health" {
  description = "A 0- or 1-entry list of Health Check resource created"
  value       = flatten([ for be in module.backend : be.health ])
}

output "negs" {
  description = "A map from Compute Zone names to the NEG resource records"
  value       = 0 < length(module.backend) ? module.backend[0].negs : {}
}

output "keys" {
  description = "The hostnames minus '|..' suffixes; keys to below maps"
  value       = module.ingress.keys
}

output "dns" {
  description = "A map from hostname to DNS `A` Record resources created"
  value       = module.ingress.dns
}

output "ip" {
  description = "A 0- or 1-entry list of IP Address resource created"
  value       = module.ingress.ip
}

output "f80" {
  description = (
    "A 0- or 1-entry list of port-80 Forwarding Rule resource created" )
  value       = module.ingress.f80
}

output "f443" {
  description = (
    "A 0- or 1-entry list of port-443 Forwarding Rule resource created" )
  value       = module.ingress.f443
}

output "http" {
  description = (
    "A 0- or 1-entry list of Target HTTP Proxy resource created" )
  value       = module.ingress.http
}

output "https" {
  description = (
    "A 0- or 1-entry list of Target HTTPS Proxy resource created" )
  value       = module.ingress.https
}

output "lb-certs" {
  description = "A map from hostname to 'Classic' cert resources created"
  value       = module.ingress.lb-certs
}

output "cert-map" {
  description = "A 0- or 1-entry list of cert-map-simple module record"
  value       = module.ingress.cert-map
}

output "cert-map-id" {
  description = "A 0- or 1-entry list of certificate map ID"
  value       = module.ingress.cert-map-id
}

output "url-map" {
  description = "A 0- or 1-entry list of URL Map resource created"
  value       = module.ingress.url-map
}

output "redir-map" {
  description = (
    "A 0- or 1-entry list of resource for URL Map to redirect to HTTPS" )
  value       = module.ingress.redir-map
}

