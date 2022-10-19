# terraform-google-ingress-to-gke

A Terraform module for building more reliable ingresses to GKE workloads.
Use of the module can be very simple while also allowing great flexibility
and power, including multi-region support.


## Contents

* [Simplest Example](#simplest-example)
* [Benefits](#benefits)
* [Best Example](#best-example)
* [2nd-Best Example](#2nd-best-example)
* [Detailed Documentation](#detailed-documentation)
* [Usage](#usage)
* [Infrastructure Created](#infrastructure-created)
* [Limitations](#limitations)
* [Input Variables](#input-variables)

This module is not yet in any Terraform module registry.  We plan to
register it but are focusing on the first users and also increasing
test coverage before that.


## Simplest Example

First, let's see how simple this module can be to use.  This invocation
of the module configures global HTTP and HTTPS load balancing to a
Kubernetes Workload running in 3 regional GKE Clusters using a "Classic"
load-balancer-authorized SSL certificate (including allocating a health
check and an IP address and arranging for http:// requests to be redirected
to https://, but not setting up DNS records for it).

    module "my-ingress" {
      source            = (
        "github.com/TyeMcQueen/terraform-google-ingress-to-gke" )
      clusters          = {
      # Location(Region)   GKE Cluster Name
        us-central1     = "gke-my-product-prd-usc1"
        asia-east1      = "gke-my-product-prd-ape1"
        europe-west1    = "gke-my-product-prd-euw1"
      }
      neg-name          = "my-svc"
      hostnames         = [ "svc.my-product.example.com" ]
      create-lb-certs   = true
    }

This provides most of the benefits described below, but not the benefits
from using a certificate map from Cloud Certificate Manager.

Before you can `apply` such an invocation, you need to deploy your Workload
to each of the referenced Clusters and it must include a Service object
with an annotation similar to:

    cloud.google.com/neg: '{"exposed_ports": {"80": {"name": "my-svc"}}}'

This step creates the Network Endpoint Group (one per Compute Zone) that
routes requests to any healthy instances of your Workload.  The "name" in
the annotation must match the `neg-name` you pass to this module.

The LB-authorized certificate will not become active until your hostname
is set up in DNS to point to the allocated IP address (plus about 20 minutes
to finish the automated authorization process).


## Benefits

This module makes it easy to allocate GCP Global L7 (HTTP/S) Load Balancing
to route to a Kubernetes Workload running on 1 or more GKE Clusters (Google
Kubernetes Engine).  There are several advantages to this approach over using
GKE annotations to have GKE tooling automatically create such infrastructure.

### Multi-Region Support

GKE Annotations do not support setting up a multi-region ingress.  This
module allows a single IP address to be efficiently and reliably routed
to multiple Regional GKE Clusters.  The routing is efficient because
traffic from anywhere in the world will enter GCP's network via the closest
GCP Region and because traffic is routed from there to the closest Region
where you have a healthy Workload.  It is reliable because traffic is
automatically routed to the next-closest healthy Workload if the closest
Workload is not currently healthy.

### Better Reliability

We have observed many (but not frequent) outages in services due to bugs and
limitations in the GKE tooling that creates load balancing infrastructure
from GKE annotations.  The problem is made worse because these outages often
involve destruction of SSL Certificates and so often have a minimum duration
of about 20 minutes and often take longer because figuring out how to work
around the bug or limitation is often difficult and/or time-consuming.

Even if you make a mistake with this module that would trigger the deletion
of an SSL Certificate, you can see this during the `plan` phase and thus not
`apply` the change and completely avoid an outage while you fix the cause.

### Better Visibility

Because the creation of all of this infrastructure is done by Terraform,
you can immediately see the progress made and exactly when and why any step
fails.  This means that work to correct the cause of the failure can start
immediately and without having to search for details about what went wrong.

### Can Use A Certificate Map

You can use GCP's new Cloud Certificate Manager to create a certificate
map which provides more reliability and security benefits and can auto-renew
even wildcard certs.  See the [certificate-map-simple module](
https://github.com/TyeMcQueen/terraform-google-certificate-map-simple) for
more about these benefits.

### More Flexibility

This module supports full control over nearly every aspect of the creation
of this infrastructure.  You can do more advanced configurations like:

* Share a URL Map and/or an IP Address between multiple Workloads
* Choose between Classic and Modern L7 LB schemes
* Use any advanced URL Map features
* Migrate traffic with no interruption of service


## Best Example

This example provides *all* of the benefits described above and is still
very simple but requires that your hostnames are part of a GCP-Managed
DNS Zone that your Terraform workspace has write access to.  It even
creates the DNS records for your hostnames.

    module "my-ingress" {
      source            = (
        "github.com/TyeMcQueen/terraform-google-ingress-to-gke" )
      cluster-objects   = [
        google_container_cluster.usc1,
        google_container_cluster.euw1,
        google_container_cluster.ape1,
      ]
      neg-name          = "my-svc"
      map-name          = "my-svc"
      hostnames         = [ "honeypot", "svc" ]
      reject-honeypot   = true
      dns-zone-ref      = "my-zone"
      dns-add-hosts     = true
    }

By using a Cloud Certificate Manager certificate map you get additional
benefits including a "honeypot" hostname, a certificate for which will be
given to hackers that hit your load balancer IP address using HTTPS but
with some random hostname.  This prevents the hackers from trivially being
able to discover the hostname to use for further scanning/attack attempts.
And `reject-honeypot` means requests that use the honeypot hostname will
not even be routed to your Workload.

The [certificate-map-simple module](
https://github.com/TyeMcQueen/terraform-google-certificate-map-simple)
that this module uses fully documents these additional benefits.

### Avoiding Nested Modules

This module is mostly just a convenient wrapper around two other modules,
one of which can invoke a third module.

* [backend-to-gke](
    https://github.com/TyeMcQueen/terraform-google-backend-to-gke) - Creates
    the Backend Service that routes to the Network Endpoint Groups that GKE
    manages for your workload
* [http-ingress](
    https://github.com/TyeMcQueen/terraform-google-http-ingress) - Assembles
    all of the load balancing pieces together
* [certificate-map-simple](
    https://github.com/TyeMcQueen/terraform-google-certificate-map-simple) -
    Called by http-ingress to create the Cloud Certificate Manager resources

The above example is the same as the following example where the use of the
other modules is made explicit.  This approach is recommended by Terraform
as a best practice for combining modules.  But you can start with the simpler
usage above and then move to this more verbose usage if and when the need
arises.

    module "my-backend" {
      source            = (
        "github.com/TyeMcQueen/terraform-google-backend-to-gke" )
      cluster-objects   = [
        google_container_cluster.usc1,
        google_container_cluster.euw1,
        google_container_cluster.ape1,
      ]
      neg-name          = "my-svc"
    }

    module "my-cert-map" {
      source            = (
        "github.com/TyeMcQueen/terraform-google-certificate-map-simple" )
      name-prefix       = "my-svc-"
      map-name1         = "my-svc"
      hostnames1        = [ "honeypot", "svc" ]
      dns-zone-ref      = "my-zone"
    }

    module "my-ingress" {
      source            = (
        "github.com/TyeMcQueen/terraform-google-http-ingress" )
      name-prefix       = "my-svc-"
      hostnames         = [ "honeypot", "svc" ]
      reject-honeypot   = true
      dns-zone-ref      = "my-zone"
      dns-add-hosts     = true
      backend-ref       = module.my-backend.backend.id
      cert-map-ref      = module.my-cert-map[0].map-id1[0]
    }


## 2nd-Best Example

If your Terraform workspace can't manage the DNS Zone for your hostname(s),
then you can still get the "honeypot" benefit of using a certificate map
by using "modern" LB-authorized certificates (by appending "|LB" to each
hostname).

    module "my-ingress" {
      source            = (
        "github.com/TyeMcQueen/terraform-google-ingress-to-gke" )
      cluster-objects   = [ google_container_cluster.usc1 ]
      neg-name          = "my-svc"
      map-name          = "my-svc"
      hostnames         = [
        "honeypot.my-product.example.com|LB",
        "my-svc.my-product.example.com|LB",
      ]
      reject-honeypot   = true
    }

This way you lose some minor resiliency benefits of using DNS-authorized
certificates, but those may not be worth the added complexity of using
DNS-authorized certs when the authorization can't be automated.  Though, if
you want to migrate traffic to this new configuration without any disruption,
then you will need to use DNS-authorized certificates or temporarily use
customer-managed certificates.


## Detailed Documentation

This module is very flexible/powerful, supporting a lot of options that give
you full control over your infrastructure.  We encourage you to start with
one of the simple examples (above) and customize that as needed.  If you
try to look at all of the possible options, it is easy to be overwhelmed.

Most aspects of the module are documented from multiple angles (and
some of the linked documentation is from the other modules).  When
you are ready to customize, you should probably start with the [Usage](
#usage) documentation.  Depending on what angle you want to look
from, you can also look at any of these lists:

* [What infrastructure can be created](#infrastructure-created)
* Input [variables.tf](/variables.tf) or the [sorted list of links](
    #input-variables) to the documentation for each input.
* [Known limitations](#limitations)
* [outputs.tf](/outputs.tf) simply lists all of the outputs from this module.


## Usage

* [Multiple Clusters](#multiple-clusters)
* [Option Toggles](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Usage.md#option-toggles)
* [Certificate Types](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Usage.md#certificate-types)
* [Hostnames](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Usage.md#hostnames)
* [Major Options](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Usage.md#major-options)

### Multiple Clusters

Your ingress can route to multiple GKE Clusters, providing a reliable and
efficient multi-region ingress (as described at [Multi-Region Support](
/README.md#multi-region-support)).

There are two ways to specify the GKE Cluster(s) that your workload is
deployed to.  First, you can list Cluster resource objects for Clusters
that you create as part of this Terraform workspace (or that you loaded
using a `data "google_container_cluster"` block).

      cluster-objects   = [
        google_container_cluster.usc1,
        google_container_cluster.euw1,
        google_container_cluster.ape1,
      ]

Second, you can list Region (or Zone) name and Cluster name in a map:

      clusters = {
      # Location(Region)   GKE Cluster Name
        us-central1     = "gke-my-product-prd-usc1"
        asia-east1      = "gke-my-product-prd-ape1"
        europe-west1    = "gke-my-product-prd-euw1"
      }

And you can combine both methods, specifying some cluster(s) in one and
some in the other.

Because a single NEG name is used by this module, you can't use (for a
single ingress) 2 Clusters in the same region nor Clusters that overlap
zones.  Trying to do so would cause failures when you deployed to those
Clusters with the required annotation that creates a NEG in each zone
(which must be done before `terraform apply` with this module will
succeed).


## Infrastructure Created

* [Backend Service](
    https://github.com/TyeMcQueen/terraform-google-backend-to-gke#backend-service)
* [Health Check](
    https://github.com/TyeMcQueen/terraform-google-backend-to-gke#health-check)
* [IP Address](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Created.md#ip-address)
* [Classic SSL Certificates](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Created.md#classic-ssl-certificates)
* [Modern SSL Certificates](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Created.md#modern-ssl-certificates)
* [DNS `A` Records](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Created.md#dns-a-records)
* [Target Proxies, Forwarding Rules](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Created.md#target-proxies-forwarding-rules)
* [Redirect URL Map](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Created.md#redirect-url-map)
* [Main URL Map](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Created.md#main-url-map)


## Limitations

* [Google Providers](#google-providers)
* [Beware of Deletions](
    https://github.com/TyeMcQueen/terraform-google-certificate-map-simple/#deletions)
* [Error Handling](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Limitations.md#error-handling)
* [Unused Resource Types](
    https://github.com/TyeMcQueen/terraform-google-http-ingress/blob/main/docs/Limitations.md#unused-resource-types)
* [Handling Cluster Migration](
    https://github.com/TyeMcQueen/terraform-google-backend-to-gke#handling-cluster-migration)

### Google Providers

This module uses the `google-beta` provider and allows the user to control
which version (via standard Terraform features for such).  We would like
to allow the user to pick between using the `google` and the `google-beta`
provider, but Terraform does not allow such flexibility with provider
usage in modules at this time.

You must use at least v4.30 of the `google-beta` provider as earlier
versions did not support Certificate Manager.

You must use at least Terraform v0.13 as the module uses some features
that were not available in earlier versions.


## Input Variables

* [bad-host-backend](/variables.tf#L586)
* [bad-host-code](/variables.tf#L567)
* [bad-host-host](/variables.tf#L600)
* [bad-host-path](/variables.tf#L615)
* [bad-host-redir](/variables.tf#L633)
* [cert-map-ref](/variables.tf#L235)
* [cluster-objects](/variables.tf#L40)
* [clusters](/variables.tf#L27)
* [create-lb-certs](/variables.tf#L100)
* [description](/variables.tf#L340)
* [dns-add-hosts](/variables.tf#L383)
* [dns-ttl-secs](/variables.tf#L392)
* [dns-zone-ref](/variables.tf#L166)
* [health-interval-secs](/variables.tf#L412)
* [health-path](/variables.tf#L403)
* [health-ref](/variables.tf#L200)
* [health-timeout-secs](/variables.tf#L422)
* [healthy-threshold](/variables.tf#L443)
* [hostnames](/variables.tf#L53)
* [http-redir-code](/variables.tf#L523)
* [ip-addr-ref](/variables.tf#L215)
* [ip-is-shared](/variables.tf#L367)
* [labels](/variables.tf#L351)
* [lb-cert-refs](/variables.tf#L274)
* [lb-scheme](/variables.tf#L139)
* [log-sample-rate](/variables.tf#L458)
* [map-cert-ids](/variables.tf#L256)
* [map-name](/variables.tf#L115)
* [max-rps-per](/variables.tf#L469)
* [name-prefix](/variables.tf#L327)
* [neg-name](/variables.tf#L5)
* [project](/variables.tf#L314)
* [quic-override](/variables.tf#L489)
* [redirect-http](/variables.tf#L511)
* [reject-honeypot](/variables.tf#L546)
* [unhealthy-threshold](/variables.tf#L432)
* [url-map-ref](/variables.tf#L289)
