#!/bin/bash
perl $RESEQTRACK/scripts/file/run_tree_for_ftp.pl \
  $RESEQTRACK_DB_ARGS \
  -skip_load -skip_archive \
  -dir_to_tree /nfs/faang/vol1/ftp \
  -staging_dir /hps/cstor01/nobackup/faang/archive-staging/ftp \
  -log_dir /nfs/1000g-work/G1K/work/rseqpipe/faang_ftp_tree_pgtrace_logs