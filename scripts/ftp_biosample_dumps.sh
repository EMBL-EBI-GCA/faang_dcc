#!/bin/bash

diff -q /hps/cstor01/nobackup/faang/farmpipe/supporting-info/faang_samples_in_biosamples.tsv /nfs/faang/vol1/ftp/biosamples/faang_samples_in_biosamples.tsv 1>/dev/null
if ! [[ $? == "0" ]]
then
  echo "Not the same"
else
  echo "The same"
fi






#cp /hps/cstor01/nobackup/faang/farmpipe/supporting-info/faang_samples_in_biosamples.tsv /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/faang_samples_in_biosamples.tsv \
#&& cp /hps/cstor01/nobackup/faang/farmpipe/supporting-info/rst_samples.tsv /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/rst_samples.tsv \
#&& perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/load_files.pl -dbhost mysql-rs-faang-prod -dbport 4478 -dbuser g1krw -dbpass thousandgenomes -dbname faang_archive_staging_track -run -update -do_md5 -file /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/faang_samples_in_biosamples.tsv \
#&& perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/load_files.pl -dbhost mysql-rs-faang-prod -dbport 4478 -dbuser g1krw -dbpass thousandgenomes -dbname faang_archive_staging_track -run -update -do_md5 -file /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/rst_samples.tsv \
#&& perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/archive_files.pl -dbhost mysql-rs-faang-prod -dbport 4478 -dbuser g1krw -dbpass thousandgenomes -dbname faang_archive_staging_track -action  archive -skip -run -priority 99 -file /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/faang_samples_in_biosamples.tsv \
#&& perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/archive_files.pl -dbhost mysql-rs-faang-prod -dbport 4478 -dbuser g1krw -dbpass thousandgenomes -dbname faang_archive_staging_track -action  archive -skip -run -priority 99 -file /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/rst_samples.tsv \
#&& perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/cleanup_archive.pl -dbhost mysql-rs-faang-prod -dbport 4478 -dbuser g1krw -dbpass thousandgenomes -dbname faang_archive_staging_track