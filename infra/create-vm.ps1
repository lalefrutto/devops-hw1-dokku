# Creates the Dokku VM on Windows (Hyper-V + Multipass) and runs install-dokku.sh on it.
# Usage (from the repo root):  powershell -ExecutionPolicy Bypass -File infra\create-vm.ps1
$ErrorActionPreference = 'Stop'
$vm = 'dokku'

multipass launch 24.04 --name $vm --cpus 2 --memory 4G --disk 30G
multipass transfer infra/install-dokku.sh infra/install-runner.sh "${vm}:/home/ubuntu/"
multipass exec $vm -- sudo bash /home/ubuntu/install-dokku.sh
multipass info $vm
