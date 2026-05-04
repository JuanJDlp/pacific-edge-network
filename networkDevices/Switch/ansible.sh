#!/bin/bash

case "$1" in

    vlans)
        ansible-playbook playbooks/vlans.yml
        ;;

    interfaces)
        ansible-playbook playbooks/interfaces.yml
        ;;

    backup)
        ansible-playbook playbooks/backup.yml
        ;;

    all)
        ansible-playbook playbooks/main.yml
        ;;

    *)
        echo "Usage:"
        echo "./ansible.sh vlans"
        echo "./ansible.sh interfaces"
        echo "./ansible.sh backup"
        echo "./ansible.sh all"
        ;;
esac