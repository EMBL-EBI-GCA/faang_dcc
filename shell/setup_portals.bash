#!/bin/bash

ME=`whoami`
if [ $ME != reseq_adm ]; then
  echo run this script as reseq_adm
  exit 1
fi

BASE=${BASE:-/nfs/public/rw/reseq-info}

for ES_BASE in $BASE/elasticsearch $BASE/elasticsearch_staging; do
  umask 0022
  mkdir -p $ES_BASE $ES_BASE/gca_elasticsearch $ES_BASE/snapshot_repo $ES_BASE/var
  git clone ssh://git@github.com/EMBL-EBI-GCA/gca_elasticsearch.git $ES_BASE/gca_elasticsearch
  mkdir -p $ES_BASE/gca_elasticsearch/config/scripts

  for type in cellLine donor file; do
    ln -sfT $ES_BASE/gca_hipsci_browser/elasticsearch_settings/scripts/hipsci_${type}_transform.groovy $ES_BASE/gca_elasticsearch/config/scripts/hipsci_${type}_transform.groovy
  done

  umask 0002
  mkdir -p $ES_BASE/var/log $ES_BASE/snapshot_repo/hipsci_repo
done

FAANG_WEBSITE_BASE=$BASE/faang_website_staging

umask 0022
mkdir -p $FAANG_WEBSITE_BASE $FAANG_WEBSITE_BASE/var/log $FAANG_WEBSITE_BASE/var/run $FAANG_WEBSITE_BASE/www
git clone ssh://git@github.com/EMBL-EBI-GCA/gca_elasticsearch.git $FAANG_WEBSITE_BASE/gca_elasticsearch
git clone ssh://git@github.com/FAANG/faang-portal-frontend.git $FAANG_WEBSITE_BASE/faang-portal-frontend
git clone ssh://git@github.com/FAANG/faang-portal-backend.git $FAANG_WEBSITE_BASE/faang-portal-backend

umask 0002
mkdir -p $FAANG_WEBSITE_BASE/var/log/hx $FAANG_WEBSITE_BASE/var/run/hx

FAANG_WEBSITE_BASE=$BASE/faang_website

umask 0022
mkdir -p $FAANG_WEBSITE_BASE $FAANG_WEBSITE_BASE/var/log $FAANG_WEBSITE_BASE/var/run $FAANG_WEBSITE_BASE/www
git clone ssh://git@github.com/EMBL-EBI-GCA/gca_elasticsearch.git $FAANG_WEBSITE_BASE/gca_elasticsearch
git clone ssh://git@github.com/FAANG/faang-portal-frontend.git $FAANG_WEBSITE_BASE/faang-portal-frontend

umask 0002
mkdir -p $FAANG_WEBSITE_BASE/var/log/hx $FAANG_WEBSITE_BASE/var/run/hx

FAANG_BASE=$BASE/faang_staging

umask 0022
mkdir -p $FAANG_BASE $FAANG_BASE/www $FAANG_BASE/rule_sets 
git clone ssh://git@github.com/FAANG/faang-metadata.git $FAANG_BASE/rule_sets/faang-metadata
git clone ssh://git@github.com/FAANG/faang-validate.git $FAANG_BASE/www/faang-validate
git clone ssh://git@github.com/EMBL-EBI-GCA/BioSD.git $FAANG_BASE/www/BioSD

FAANG_BASE=$BASE/faang
umask 0022
mkdir -p $FAANG_BASE $FAANG_BASE/www $FAANG_BASE/rule_sets 
git clone ssh://git@github.com/FAANG/faang-metadata.git $FAANG_BASE/rule_sets/faang-metadata
git clone ssh://git@github.com/FAANG/faang-validate.git $FAANG_BASE/www/faang-validate
git clone ssh://git@github.com/EMBL-EBI-GCA/BioSD.git $FAANG_BASE/www/BioSD