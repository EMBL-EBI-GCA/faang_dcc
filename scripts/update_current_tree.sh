#!/bin/bash
perl $RESEQTRACK/scripts/file/run_tree_for_ftp.pl \
  $RESEQTRACK_DB_ARGS \
  -dir_to_tree /nfs/faang/vol1/ftp \
  -staging_dir /hps/cstor01/nobackup/faang/archive-staging/ftp \
  -log_dir /homes/farmpipe/logs/faang_ftp_tree_logs
