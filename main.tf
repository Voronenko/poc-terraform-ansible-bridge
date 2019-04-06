data "external" "ansible" {
  program  = [ "tf_ansible_vault.sh", "env-default-secure-vars.yml"]
}

output "shared_secure_var1" {
  value = "${data.external.ansible.result.shared_secure_var1}"
}

output "shared_secure_var2" {
  value = "${data.external.ansible.result.shared_secure_var2}"
}


