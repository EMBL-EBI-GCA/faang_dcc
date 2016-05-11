#!/bin/bash
perl $RESEQTRACK/scripts/file/run_tree_for_ftp.pl \
  $RESEQTRACK_DB_ARGS \
  -dir_to_tree /hps/cstor01/nobackup/faang/archive-staging/ftp \
  -staging_dir /hps/cstor01/nobackup/faang/archive-staging/ftp \
  -old_tree_dir /nfs/faang/vol1/ftp \
  -old_changelog_dir /nfs/faang/vol1/ftp \
  -log_dir /homes/farmpipe/logs/faang_ftp_tree_logs \
  -options dont_use_nlink=1