#!/bin/bash

diff -q /hps/cstor01/nobackup/faang/farmpipe/supporting-info/faang_samples_in_biosamples.tsv /nfs/faang/vol1/ftp/biosamples/faang_samples_in_biosamples.tsv 1>/dev/null
if ! [[ $? == "0" ]]
then
  cp -p /hps/cstor01/nobackup/faang/farmpipe/supporting-info/faang_samples_in_biosamples.tsv /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/faang_samples_in_biosamples.tsv \
  && perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/load_files.pl -dbhost $RESEQTRACK_DB_HOST -dbport $RESEQTRACK_DB_PORT -dbuser $RESEQTRACK_DB_USER -dbpass $RESEQTRACK_DB_PASS -dbname $RESEQTRACK_DB_NAME -run -update -do_md5 -file /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/faang_samples_in_biosamples.tsv \
  && perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/archive_files.pl -dbhost $RESEQTRACK_DB_HOST -dbport $RESEQTRACK_DB_PORT -dbuser $RESEQTRACK_DB_USER -dbpass $RESEQTRACK_DB_PASS -dbname $RESEQTRACK_DB_NAME -action  archive -skip -run -priority 99 -file /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/faang_samples_in_biosamples.tsv
else
  :
fi;
diff -q /hps/cstor01/nobackup/faang/farmpipe/supporting-info/biosample_summary.tsv /nfs/faang/vol1/ftp/biosamples/biosample_summary.tsv 1>/dev/null
if ! [[ $? == "0" ]]
then
  cp -p /hps/cstor01/nobackup/faang/farmpipe/supporting-info/biosample_summary.tsv /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/biosample_summary.tsv \
  && perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/load_files.pl -dbhost $RESEQTRACK_DB_HOST -dbport $RESEQTRACK_DB_PORT -dbuser $RESEQTRACK_DB_USER -dbpass $RESEQTRACK_DB_PASS -dbname $RESEQTRACK_DB_NAME -run -update -do_md5 -file /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/biosample_summary.tsv \
  && perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/archive_files.pl -dbhost $RESEQTRACK_DB_HOST -dbport $RESEQTRACK_DB_PORT -dbuser $RESEQTRACK_DB_USER -dbpass $RESEQTRACK_DB_PASS -dbname $RESEQTRACK_DB_NAME -action  archive -skip -run -priority 99 -file /hps/cstor01/nobackup/faang/archive-staging/ftp/biosamples/biosample_summary.tsv
else
  :
fi;
perl /nfs/production/reseq-info/work/farmpipe/reseqtrack/scripts/file/cleanup_archive.pl -dbhost $RESEQTRACK_DB_HOST -dbport $RESEQTRACK_DB_PORT -dbuser $RESEQTRACK_DB_USER -dbpass $RESEQTRACK_DB_PASS -dbname $RESEQTRACK_DB_NAME