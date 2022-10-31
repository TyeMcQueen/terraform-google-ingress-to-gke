

###--- Required inputs ---###

variable "neg-name" {
  description   = <<-EOD
    Required name assigned to the Network Endpoint Group you created via
    an annotation added to your Kubernetes Service resource.

    Example: neg-name = "api"
    would work with the following Service annotation:
      cloud.google.com/neg: '{"exposed_ports": {"80": {"name": "api"}}}'
  EOD
  type          = string

  validation {
    condition       = "" != var.neg-name
    error_message   = "Must not be \"\"."
  }
}


###--- Most-used inputs ---###

# At least one of "clusters" and "cluster-objects" must not be empty.

variable "clusters" {
  description   = <<-EOD
    A map from GCP Compute Region (or Zone) name to GKE Cluster Name in
    that Region/Zone.  The cluster name can be "$${project-id}/$${name}"
    to use a cluster in a different GCP Project.  This and/or
    `cluster-objects` must not be empty.
    Example:
      clusters = { us-central1 = "gke-my-product-prd-usc1" }
  EOD
  type          = map(string)
  default       = {}
}

variable "cluster-objects" {
  description   = <<-EOD
    A list of google_container_cluster resource objects.  Usually, each
    is a reference to a resource or data declaration.  But all that is
    required is that each object have an appropriate value for
    `node_locations` (a list of Compute Zone names).
    Example: cluster-list = [
      google_container_cluster.usc, data.google_container_cluster.legacy ]
  EOD
  type          = list(object({node_locations=list(string)}))
  default       = []
}

variable "hostnames" {
  description   = <<-EOD
    The host name(s) used to connect to your backend.

    Any "short" hostname (one that contains no "." characters or has a
    final "." character) will have the domain referenced via `dns-zone-ref`
    appended to it.  [Note that the final "." here has the opposite meaning
    of a final "." character in some other DNS situations.]

    If a URL map is created and you list at least one hostname, then the URL
    map will (by default) only route requests for the listed hostname(s) to
    your backend.

    If you set `dns-add-hosts = true`, then each "short" hostname will have
    DNS `A` records created in the referenced GCP-Managed DNS Zone.

    If `map-name` is not blank, then a "modern" DNS-authorized certificate
    (by default) will be created for each hostname.  Those will all be
    placed into a certificate map.

    If you set `create-lb-certs = true`, then a "classic" LB-authorized
    certificate will be created (by default) for each hostname.

    Appending just "|" to a hostname prevents a certificate from being
    created.  Appending "|LB" means the certificate will be LB-authorized.
    Appending "|" followed by a numeric offset will use a certificate's
    `.id` from `map-cert-ids`.

    For more details:
    https://github.com/TyeMcQueen/terraform-google-https-ingress/docs/Usage.md#hostnames

    Example:
      hostnames     = [ "my-api", "web.my-product.example.com" ]

    Example:
      hostnames     = [ "honeypot", "svc.stg.|LB", "*.my-domain.com|0" ]
      map-cert-ids  = [
        google_certificate_manager_certificate.wild.id,
      ]
  EOD
  type          = list(string)
  default       = []
}


###--- Major options ---###

variable "create-lb-certs" {
  description   = <<-EOD
    Set to `true` to have a "classic" LB-authorized certificate created (by
    default) for each hostname in `hostnames`.  Each created certificate
    will be added to the Target HTTPS Proxy (if such is created).

    Hostnames ending in just "|" will have no certificate created for them
    (which usually means a certificate covering that hostname is provided
    via `lb-cert-refs`).  A "|LB" suffix on a hostname is ignored and other
    uses of "|" are not supported when `create-lb-certs` is `true`.
  EOD
  type          = bool
  default       = false
}

variable "map-name" {
  description   = <<-EOD
    The name of the certificate map to create.  If left as "", then no
    certificate map is created.

    If not "", then a DNS-authorized certificate is created (by default) for
    each hostname in `hostnames` and a certificate map entry is added for the
    hostname and pointing to that created certificate.  The entry for the
    first hostname will be "PRIMARY" (handed out if a request's hostname
    does not match any of the other entries).

    Hostnames that end in "|LB" have a "modern" LB-authorized certificate
    created for them instead.  Hostnames that end in just "|" have no
    certificate created and are not added to the certificate map.  Hostnames
    that end in "|" followed by a numeric offset will be added to the
    map using the certificate `.id` at that offset in `map-cert-ids` (no
    certificate is created).

    Example: map-name = "my-cert-map"
  EOD
  type          = string
  default       = ""
}

variable "lb-scheme" {
  description   = <<-EOD
    Defaults to "EXTERNAL_MANAGED" ["Modern" Global L7 HTTP(S) LB].  Can be
    set to "EXTERNAL" ["Classic" Global L7 HTTP(S) LB].  Or set to "" to
    deprovision most of the LB components so they can then be fully recreated.

    Switching between "EXTERNAL" and "EXTERNAL_MANAGED" may leave Terraform
    unable to automatically recreate the needed components in the proper
    order to successfully complete the transition.  If you switch to "" and
    apply and then switch to your desired value and apply again, then the
    reconstruction should work fine.  This will not remove components that
    do not need to be recreated, especially the allocated IP address and SSL
    certificate(s).
  EOD
  type          = string
  default       = "EXTERNAL_MANAGED"

  validation {
    condition       = ( var.lb-scheme == "" ||
      var.lb-scheme == "EXTERNAL" || var.lb-scheme == "EXTERNAL_MANAGED" )
    error_message   = "Must be \"EXTERNAL\", \"EXTERNAL_MANAGED\", or \"\"."
  }
}


###--- References to resources created elsewhere ---###

variable "dns-zone-ref" {
  description   = <<-EOD
    Either the name given to a GCP-Managed DNS Zone resource in this project,
    "$${project-id}/$${name}" for a DNS Zone in a different project, or blank
    to not use any of the below features.  [A full DNS Zone resource `.id`
    cannot be used here at this time.]

    If set, then you can use short names in `hostnames` ("api" for
    "api.my-domain.com" or "web.stg." for "web.stg.my-domain.com").
    If you also set `dns-add-hosts = true`, then DNS `A` records will
    be created for any short names in `hostnames`.

    WARNING: Trying to create duplicate DNS records is not currently
    detected by the GCP Terraform providers and can result in confusing
    flip-flopping of how the DNS record is defined each time the Terraform
    is applied.  So be sure to not create the same DNS record twice, once
    within this module and once outside of this module.

    If set, then you can create DNS-authorized certificates by also setting
    `map-name`.

    Examples:
      dns-zone-ref = "product-dns-zone"
      dns-zone-ref = google_dns_managed_zone.my-product.name
  EOD
  type          = string
  default       = ""

  validation {
    condition       = length(split( "/", var.dns-zone-ref )) < 3
    error_message   = "Can't be a full resource .id."
  }
}

variable "health-ref" {
  description   = <<-EOD
    Either the name given to a Health Check resource in this project,
    "$${project-id}/$${name}" for a Health Check in a different project,
    just a full Health Check resource `.id`, or "" to have a generic
    Health Check created.

    Examples:
      health-ref = "api-hc"
      health-ref = google_compute_health_check.hc.id
  EOD
  type          = string
  default       = ""
}

variable "ip-addr-ref" {
  description   = <<-EOD
    Name given to a Public IP Address allocated elsewhere.  Leave
    blank to have one allocated.  The string can also be in the format
    "$${project-id}/$${name}" to use an IP Address allocated in a different
    GCP Project.  Or you can just set it to the actual IP address.  [A full
    resource `.id` cannot be used here.]
    Examples:
      ip-addr-ref = "api-ip"
      ip-addr-ref = "35.1.2.3"
  EOD
  type          = string
  default       = ""

  validation {
    condition       = length(split( "/", var.ip-addr-ref )) < 3
    error_message   = "Can't be a full resource .id."
  }
}

variable "cert-map-ref" {
  description   = <<-EOD
    The `.id` of a certificate map created outside of this module.
    [A future release may allow other types of references after
    `data "google_certificate_manager_certificate_map"` blocks are
    supported.]

    Examples:
      cert-map-ref = google_certificate_manager_certificate_map.my-cert-map.id
      cert-map-ref = module.my-cert-map.map1[0].id
  EOD
  type          = string
  default       = ""

  validation {
    condition       = ( "" == var.cert-map-ref
      || 2 < length(split( "/", var.cert-map-ref )) )
    error_message   = "Must be a full resource .id or \"\"."
  }
}

variable "map-cert-ids" {
  description   = <<-EOD
    List of `.id`s of Cloud Certificate Manager ("modern") SSL Certificates
    that can be referenced from `hostnames` to be included in the created
    certificate map.  Append "|" followed by the index (starting at 0) in
    this list of the certificate you want to use with that hostname.

    Example:
      map-cert-ids  = [
        google_certificate_manager_certificate.api.id,
        google_certificate_manager_certificate.web.id,
      ]
      hostnames     = [ "api|0", "web|1" ]
  EOD
  type          = list(string)
  default       = []
}

variable "lb-cert-refs" {
  description   = <<-EOD
    List of references to extra "classic" SSL Certificates to be added to
    the created Target HTTPS Proxy.  Each reference can be the name given
    to a Certificate resource in this project, "$${project-id}/$${name}" for
    a Cert in a different project, or just a full Cert resource `.id`.

    Example:
      lb-cert-refs = [ "my-api-cert",
        google_compute_managed_ssl_certificate.canary-api.id ]
  EOD
  type          = list(string)
  default       = []
}

variable "url-map-ref" {
  description   = <<-EOD
    Full resource path (`.id`) for a URL Map created elsewhere (or leave as
    "" to have a generic URL Map created).  [A future release may allow other
    types of references after `data "google_compute_url_map"` blocks are
    supported.]

    If `url-map-ref` is left blank, then you must provide `backend-ref`
    which will be used by the created URL Map.

    Example: url-map-ref = google_compute_url_map.api.id
  EOD
  type          = string
  default       = ""

  validation {
    condition       = ( "" == var.url-map-ref
      || 2 < length(split( "/", var.url-map-ref )) )
    error_message   = "Must be a full resource .id or \"\"."
  }
}


###--- Generic customization inputs ---###

variable "project" {
  description   = <<-EOD
    The ID of the GCP Project that most resources will be created in.
    Defaults to "" which uses the default project of the Google client
    configuration.  Any DNS resources will be created in the project
    that owns the GCP-Managed DNS Zone referenced by `dns-zone-ref`.

    Example: project = "my-gcp-project"
  EOD
  type          = string
  default       = ""
}

variable "name-prefix" {
  description   = <<-EOD
    An optional prefix string to prepend to the `.name` of most of the GCP
    resources created by this module.  If left as "" then "$${var.neg-name}-"
    will be used.  Can be useful when migrating to or testing a new
    configuration.

    Example: name-prefix = "v2-"
  EOD
  type          = string
  default       = ""
}

variable "description" {
  description   = <<-EOD
    An optional description to be used on every created resource (except
    DNS records which don't allow descriptions).

    Example: description = "Created by Terraform module ingress-to-gke"
  EOD
  type          = string
  default       = ""
}

variable "labels" {
  description   = <<-EOD
    A map of label names and values to be applied to every created resource
    that supports labels (this includes the IP Address, the Forwarding Rules,
    the certificate map, and "modern" certificates).

    Example:
      labels = { team = "my-team", terraform = "my-workspace" }
  EOD
  type          = map(string)
  default       = {}
}


###--- Simple options ---###

variable "ip-is-shared" {
  description   = <<-EOD
    When `ip-addr-ref` is not blank, set `ip-is-shared = false` to
    still create the HTTP/S Target Proxies and Global Forwarding Rules.
    You would set `ip-is-shared = false` when re-using an IP Address
    allocated elsewhere but that is not used anywhere else.  Or when you
    actually are sharing the IP Address, in which case you would only
    set `ip-is-shared = false` for _one_ of the uses.
  EOD
  type          = bool
  default       = true
}


###--- DNS options ---###

variable "dns-add-hosts" {
  description   = <<-EOD
    Set to `true` to create DNS `A` records for each entry in `hostnames`
    that is "short" (contains no "." or ends in a  ".").
  EOD
  type          = bool
  default       = false
}

variable "dns-ttl-secs" {
  description   = <<-EOD
    Time-To-Live, in seconds, for created DNS records.
  EOD
  type          = number
  default       = 300
}


###--- Health check options ---###

variable "health-path" {
  description   = <<-EOD
    Path to use in created Health Check (only if `health-ref` left as "").
    Example: health-path = "/ready"
  EOD
  type          = string
  default       = "/"
}

variable "health-interval-secs" {
  description   = <<-EOD
    How long to wait between health checks, in seconds.

    Example: health-interval-sec = 10
  EOD
  type          = number
  default       = 5
}

variable "health-timeout-secs" {
  description   = <<-EOD
    How long to wait for a reply to a health check, in seconds.

    Example: health-timeout-sec = 10
  EOD
  type          = number
  default       = 5
}

variable "unhealthy-threshold" {
  description   = <<-EOD
    How many failed health checks before a Backend instance is considered
    unhealthy (thus no longer routing requests to it).

    Example: unhealthy-threshold = 1
  EOD
  type          = number
  default       = 2
}

variable "healthy-threshold" {
  description   = <<-EOD
    How many successful health checks to an unhealthy Backend instance
    are required before the Backend is considered healthy (thus again
    routing requests to it).

    Example: healthy-threshold = 1
  EOD
  type          = number
  default       = 2
}


###--- Backend options ---###

variable "log-sample-rate" {
  description   = <<-EOD
    The fraction [0.0 .. 1.0] of requests to your Backend Service that should
    be logged.  Setting this to 0.0 will set `log_config.enabled = false`.

    Example: log-sample-rate = 0.01
  EOD
  type          = number
  default       = 1.0
}

variable "max-rps-per" {
  description   = <<-EOD
    The maximum requests-per-second that load balancing will send per
    endpoint (per pod); set as `max_rate_per_endpoint` in the created
    Backend Service.  Setting this value too low can cause problems (it
    will not cause more pods to be spun up but just cause requests to
    be rejected).  It is possible to use this as a worst-case rate limit
    that is one part of protecting your pods from excessive request
    volume, but doing this requires considerable care.  So err on the
    side of setting it too high rather than too low.

    Example: max-rps-per = 5000
  EOD
  type          = number
  default       = 1000
}

variable "timeout-secs" {
  description   = <<-EOD
    The maximum number of seconds that load balancing will wait to receive a
    full response from your Workload.  You should set this value to be longer
    than you expect your Workload to ever reasonably take to respond.  Taking
    longer than this time will, unfortunately, cause load balancing to retry
    the request.  A retry can be useful in some situations, but retrying
    after a long timeout is a terrible idea (bad for user experience and
    likely just adds useless extra load to a Workload that may be responding
    slowly because it is overloaded).  You should also implement your own
    timeout in your Workload that is shorter than this value.
  EOD
  type          = number
  default       = 30
}

variable "security-policy" {
  description   = <<-EOD
    The `.id` of a Cloud Armor security policy to apply to your Workload.

    Example: security-policy = google_compute_security_policy.my-api.id
  EOD
  type          = string
  default       = ""
}

variable "session-affinity" {
  description   = <<-EOD
    Defaults to "NONE".  Can be set to "CLIENT_IP" to use a best-effort
    session affinity based on the client's IP address.
  EOD
  type          = string
  default       = "NONE"

  validation {
    condition       = (
      var.session-affinity == "NONE" || var.session-affinity == "CLIENT_IP" )
    error_message   = "Must be \"NONE\" or \"CLIENT_IP\"."
  }
}

variable "iap-id" {
  description   = <<-EOD
    The OAuth2 Client ID required for Identity-Aware Proxy.  Setting this
    causes IAP to be enabled.

    Example: iap-id = google_iap_client.my-api.client_id
  EOD
  type          = string
  default       = ""
}

variable "iap-secret" {
  description   = <<-EOD
    The OAuth2 Client Secret required for Identity-Aware Proxy.

    Example: iap-secret = google_iap_client.my-api.secret
  EOD
  type          = string
  default       = ""
}


###--- HTTPS proxy options ---###

variable "quic-override" {
  description   = <<-EOD
    For the created https_target_proxy, whether to explicitly enable or
    disable negotiating QUIC optimizations with clients.  The default is
    "NONE" which uses the current default ("DISABLE" at the time of
    this writing).  Can be "ENABLE" or "DISABLE" (or "NONE").
  EOD
  type          = string
  default       = "NONE"

  validation {
    condition       = ( var.quic-override == "NONE" ||
      var.quic-override == "ENABLE" || var.quic-override == "DISABLE" )
    error_message   = "Must be \"NONE\", \"ENABLE\", or \"DISABLE\"."
  }
}

# TODO: ssl-policy-ref = ""


###--- HTTP-to-HTTPS redirect options ---###

variable "redirect-http" {
  description   = <<-EOD
    Set `redirect-http = false` to have http:// requests routed to your
    Workload.  By default, a separate URL Map is created for just http://
    requests that simply redirects to https://, but only if you create
    or reference at least one SSL certificate (otherwise https:// requests
    are not even supported).
  EOD
  type          = bool
  default       = true
}

variable "http-redir-code" {
  description   = <<-EOD
    The status code used when redirecting http:// requests to https://.  Only
    used if you leave `redirect-http` as `true` and create or reference at
    least one SSL certificate.  It can be 301, 302, 303, 307, or 308.  307
    is the default as mistakenly enabling the redirect using 308 can have
    long-lasting impacts that cannot be easily reverted.  Using any value
    other than 307 or 308 may cause the HTTP method to change to "GET".
  EOD
  type          = number
  default       = 307

  validation {
    condition       = (
         301 <= var.http-redir-code && var.http-redir-code <= 303
      || 307 == var.http-redir-code || 308 == var.http-redir-code )
    error_message   = "Must be 301, 302, 303, 307, or 308."
  }
}


###--- URL map options ---###

variable "exclude-honeypot" {
  description   = <<-EOD
    Set to `true` to not forward to your Backend any requests sent to the
    "honeypot" (first) hostname.  This can only work when there are at
    least 2 entries in `hostnames` and `url-map-ref` is not "".  If
    `lb-scheme` is left as "EXTERNAL_MANAGED", then `bad-host-code` must
    not be set to 0 (or `bad-host-backend` must not be "").  If `lb-scheme`
    is set to "EXTERNAL", then either `bad-host-backend` or `bad-host-host`
    must be set (not to "").

    You can set this when `lb-scheme` is "" but it will not have any impact
    in that case.  Other than that, if you set this when it cannot work, then
    the `plan` will include a parameter value that contains "ERROR" and
    mentions this setting and the `apply` will fail in a way that mentions
    the same.
  EOD
  type          = bool
  default       = false
}

variable "bad-host-code" {
  description   = <<-EOD
    When `lb-scheme` is left as "EXTERNAL_MANAGED" (and `url-map-ref` is ""),
    then the created URL Map will respond with this failure HTTP status code
    when a request is received for an unlisted hostname.  Set to 0 to have
    the URL Map ignore the request's hostname.

    Example: bad-host-code = 404
  EOD
  type          = number
  default       = 403

  validation {
    condition       = ( 0 == var.bad-host-code
        || 400 <= var.bad-host-code && var.bad-host-code < 600 )
    error_message   = "Must be 0 or 400..599."
  }
}

variable "bad-host-backend" {
  description   = <<-EOD
    When `url-map-ref` is "", the created URL Map can forward requests
    for unlisted hostnames to a different Backend Service (perhaps one
    that just rejects all requests).  For this to happen, you must set
    `bad-host-backend` to the `.id` of this alternate Backend Service.

    Example: bad-host-backend = google_compute_backend_service.reject.id
  EOD
  type          = string
  default       = ""
}

variable "bad-host-host" {
  description   = <<-EOD
    When `lb-scheme` is "EXTERNAL" (and `url-map-ref` and `bad-host-backend`
    are both ""), then the created URL Map can respond with a useless
    redirect when a request is received for an unlisted hostname ("EXTERNAL"
    URL Maps cannot directly reject requests).  Only if you set
    `bad-host-host` (not to "") will the URL Map do such redirects
    which will be to "https://$${bad-host-host}$${bad-host-path}".

    Example: bad-host-host = "localhost"
  EOD
  type          = string
  default       = ""
}

variable "bad-host-path" {
  description   = <<-EOD
    When `lb-scheme` is "EXTERNAL" and `bad-host-host` is not "", then
    the created URL Map will respond with a useless redirect to
    "https://$${bad-host-host}$${bad-host-path}" when a request is received
    for an unlisted hostname.  `bad-host-path` must start with "/".

    Example: bad-host-path = "/pound-sand"
  EOD
  type          = string
  default       = "/unknown-host"

  validation {
    condition       = "/" == substr( var.bad-host-path, 0, 1 )
    error_message   = "Must start with \"/\"."
  }
}

variable "bad-host-redir" {
  description   = <<-EOD
    When `lb-scheme` is "EXTERNAL" and `bad-host-host` is not "", then the
    created URL Map will respond with a useless redirect when a request is
    received for an unlisted hostname.  This sets the HTTP status code for
    that redirect and can be 301, 302, 303, 307, or 308.

    Example: bad-host-redir = 303
  EOD
  type          = number
  default       = 307

  validation {
    condition       = ( 301 <= var.bad-host-redir && var.bad-host-redir <= 303
      || 307 == var.bad-host-redir || 308 == var.bad-host-redir )
    error_message   = "Must be 301, 302, 303, 307, or 308."
  }
}

