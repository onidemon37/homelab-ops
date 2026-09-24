# Bootstraps the Flux Operator + FluxInstance for the prod (galactica) cluster.
# Terraform's ownership stops at the bootstrap Job (see module docs); once Flux
# adopts the Flux Operator HelmRelease and the FluxInstance, Flux/Git own them.
locals {
  control_plane_tolerations = [
    {
      key      = "node-role.kubernetes.io/control-plane"
      operator = "Exists"
      effect   = "NoSchedule"
    },
    {
      key      = "node-role.kubernetes.io/master"
      operator = "Exists"
      effect   = "NoSchedule"
    }
  ]
}

module "flux_operator_bootstrap" {
  source  = "controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes"
  version = "0.8.0"

  revision = var.bootstrap_revision

  gitops_resources = {
    instance_yaml = file("${path.root}/../../../clusters/prod/galactica/flux-system/flux-instance.yaml")
    operator_chart = {
      values_yaml = yamlencode({
        tolerations = local.control_plane_tolerations
      })
    }
  }

  job = {
    tolerations = local.control_plane_tolerations
  }
  
  # Secret content is hashed, not stored in Terraform state (see module docs).
  managed_resources = {
    secrets_yaml = yamlencode({
      apiVersion = "v1"
      kind       = "Secret"
      metadata = {
        name = "flux-system"
      }
      type = "Opaque"
      stringData = {
        githubAppID             = var.github_app_id
        githubAppInstallationID = var.github_app_installation_id
        githubAppPrivateKey     = "${trimspace(file(var.github_app_private_key_file))}\n"
      }
    })
  }
}
