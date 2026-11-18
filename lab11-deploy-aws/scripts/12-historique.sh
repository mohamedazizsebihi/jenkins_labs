#!/usr/bin/env bash
# Lab 11 - historique du job par l'API : paramètres, résultat, valideur
. "$(dirname "$0")/lib.sh"
echo "GET /job/$JOB/api/json?tree=builds[number,result,actions[parameters[name,value]]]"
jget "/job/$JOB/api/json?tree=builds[number,result,duration,actions[parameters[name,value]]]" | jq -r '
  ["BUILD","RÉSULTAT","ACTION","IMAGE_TAG","EC2_HOST","DURÉE"],
  (.builds | sort_by(.number)[] |
    (([.actions[]?.parameters[]?] | map({(.name): .value}) | add) // {}) as $p |
    ["#\(.number)", .result, ($p.ACTION // "-"), ($p.IMAGE_TAG // "-"),
     (if ($p.EC2_HOST // "") == "" then "(vide)" else $p.EC2_HOST end), "\(.duration/1000|floor) s"]) | @tsv' \
  | column -t -s $'\t'
echo
echo "Motifs : #1 EC2_HOST vide (voulu) | #2 Ansible 2.10 du système (corrigé : /opt/ansible) | #4 refusé par l'API"
echo "Version servie : $(served)"
