# Sharing sensitive variables between ansible and terraform

Simple proof of concept, how to share some sensitive variables between terraform and ansible
in a way that allows committing into git, while also being reasonably easy to decrypt, and used
natively via ansible play.

## Ansible

Let's create some sensitive variables in ansible play, `env-default-secure-vars.yml`:

```yml
---
  # Secure vars shared between terraform and ansible

  shared_secure_var1: securevalue1

  shared_secure_var2: securevalue2

```

and encrypt this file using `ansible-vault encrypt env-default-secure-vars.yml`

Let's check if ansible can work wish encrypted vars, using playbook

```yml

---
- name: TerraformAnsiblePOC
  hosts: localhost
  gather_facts: no

  pre_tasks:

    - include_vars: "env-default-secure-vars.yml"

    - include_vars:  "env-default-vars.yml"

  tasks:
    
    - debug: var="shared_secure_var1"

    - debug: var="shared_secure_var2"


```

```shell

PLAY [TerraformAnsiblePOC] *****************

TASK [debug] *******************************
ok: [localhost] => {
    "shared_secure_var1": "securevalue1"
}

TASK [debug] *******************************
ok: [localhost] => {
    "shared_secure_var2": "securevalue2"
}

PLAY RECAP ******************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0   

```

## Terraform

Now let's see how can we consume in terraform the same data ?

Fortunately, we have built-in provider external, that allows consuming json feed
returned by external program 

```tf

data "external" "ansible" {
  program  = [ "tf_ansible_vault.sh", "env-default-secure-vars.yml"]
}

output "shared_secure_var1" {
  value = "${data.external.ansible.result.shared_secure_var1}"
}

output "shared_secure_var2" {
  value = "${data.external.ansible.result.shared_secure_var2}"
}


```

Let's write shell routine, that will return json representation of the encrypted vars.

```sh

#!/bin/bash

set -ef -o pipefail
# Keep environment clean
export LC_ALL="C"
# Set variables
readonly TMP_DIR="/tmp"
readonly TMP_OUTPUT="${TMP_DIR}/$$.out"
readonly BASE_DIR="$(dirname "$(realpath "$0")")"
readonly MY_NAME="${0##*/}"
# Cleanup on exit
trap 'rm -rf ${TMP_OUTPUT}' \
  EXIT SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM

if [[ -z "$ANSIBLE_VAULT_IDENTITY_LIST" ]]
then
      echo "Please export path to vault id via ANSIBLE_VAULT_IDENTITY_LIST"
      exit 1
fi

if [[ -z "$1" ]]
then
      echo "Please provide path to secrets file"
      exit 1
fi

#echo cp $1 $TMP_OUTPUT
cp $1 $TMP_OUTPUT

ansible-vault decrypt $TMP_OUTPUT > /dev/null

python -c 'import sys, yaml, json; json.dump(yaml.load(sys.stdin), sys.stdout, indent=4)' < $TMP_OUTPUT

rm $TMP_OUTPUT


```

Checking if script works ...

```shell

./tf_ansible_vault.sh env-default-secure-vars.yml 
{
    "shared_secure_var2": "securevalue2", 
    "shared_secure_var1": "securevalue1"
}

```

and now let's check with terraform play:

```sh

terraform apply            
data.external.ansible: Refreshing state...

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

shared_secure_var1 = securevalue1
shared_secure_var2 = securevalue2


```

Seems it works. Looking very promising, but lets look into terraform.tfstate

```json

{
    "version": 3,
    "terraform_version": "0.11.11",
    "serial": 1,
    "lineage": "7f589f33-7ef8-7d45-19ab-d053412dd875",
    "modules": [
        {
            "path": [
                "root"
            ],
            "outputs": {},
            "resources": {
                "data.external.ansible": {
                    "type": "external",
                    "depends_on": [],
                    "primary": {
                        "id": "-",
                        "attributes": {
                            "id": "-",
                            "program.#": "2",
                            "program.0": "tf_ansible_vault.sh",
                            "program.1": "env-default-secure-vars.yml",
                            "result.%": "2",
                            "result.shared_secure_var1": "securevalue1",
                            "result.shared_secure_var2": "securevalue2"
                        },
                        "meta": {},
                        "tainted": false
                    },
                    "deposed": [],
                    "provider": "provider.external"
                }
            },
            "depends_on": []
        }
    ]
}


```

We see there our decrypted secure vars, so still be cautious, how you store it. Terraform has 
number of tickets around similar issues (https://github.com/hashicorp/terraform/issues/4436) for a 
few years, but no good solution until now.  

## Summary

POC shows how you can share some of your provisioning variables with terraform and back (terraform 
can generate variables yml file). Might be suitable for some situations, although not the ideal.

Check out example at  https://github.com/Voronenko/poc-terraform-ansible-bridge