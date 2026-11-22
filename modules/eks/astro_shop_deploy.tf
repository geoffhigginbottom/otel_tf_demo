resource "null_resource" "astro_shop_deploy" {
  provisioner "local-exec" {
    command = <<EOT
      ${var.eks_fargate_enabled ? "${path.module}/scripts/wait_for_fargate_profiles.sh ${var.eks_cluster_name} ${var.region} ${var.eks_cluster_name}-coredns ${var.eks_cluster_name}-default ${var.eks_cluster_name}-kube-system" : "true"}
      ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ubuntu@${self.triggers.admin_ip} \
      'set -euo pipefail; \
       /home/ubuntu/eks-s3-sync.sh pull; \
       chmod +x /home/ubuntu/astronomy_shop_release.sh; \
       /home/ubuntu/astronomy_shop_release.sh apply ${data.external.astronomy_shop_version.result.version}'
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${self.triggers.private_key_path} ubuntu@${self.triggers.admin_ip} \
      'chmod +x /home/ubuntu/astronomy_shop_release.sh 2>/dev/null; /home/ubuntu/astronomy_shop_release.sh delete' || true
    EOT
  }

  triggers = {
    admin_ip               = var.eks_admin_server_eip
    private_key_path       = var.private_key_path
    astronomy_shop_version = data.external.astronomy_shop_version.result.version
    script_hash            = filemd5("${path.module}/scripts/astronomy_shop_release.sh")
  }

  depends_on = [
    aws_instance.eks_admin_server,
    aws_eip_association.eks_admin_server_eip_assoc,
    null_resource.map_admin_vm_role,
    null_resource.sync_eks_scripts_to_s3,
    null_resource.otel_collector_deploy,
  ]
}
