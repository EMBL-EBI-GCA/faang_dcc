#!/usr/bin/env perl

=pod

=head1 LICENSE

   Copyright 2016 EMBL - European Bioinformatics Institute
   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at
     http://www.apache.org/licenses/LICENSE-2.0
   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

=head1 NAME

faang_dcc/scripts/sample_group_maintenance.pl

=head1 SYNOPSIS

This script will search for BioSamples entries tagged "project: FAANG" and add them to the FAANG sample group.

=head1 OPTIONS

  -mode, can be update, dryrun or report
    update: update the group on BioSamples
    dryrun: write sampletab and validate it, but don't update the group
    report: write a report of planned changes to STDOUT
  -biosample_api_key, API key from BioSample for updates. Must be set to allow updates
  -allow_removal  by default, we will only add samples to the sample group. With this set, we will also remove any samples that don't have the tag
  -output_dir, where should we write the output files? Defaults to current working directory
  -help, binary flag to print out the perl docs


  You probably don't want to change the following:
  -group_id, accession of the group to update. defaults to SAMEG307473
  -group_name, name of the group to use in submission. defaults to 'FAANG samples'
  -search_tag_field, which property should we check when searching for eligible samples. defaults to project
  -search_tag_value, what value should the tag field have if a sample is eligble. defaults to FAANG

=cut

use strict;
use warnings;
use BioSD;
use List::Util qw(any);
use List::Compare;
use Data::Compare;
use Time::Piece;
use Cwd;
use autodie;
use LWP::UserAgent;
use JSON;
use HTTP::Request;
use Data::Dumper;
use Getopt::Long;

my @valid_modes = qw(report update dryrun);

my $group_id          = 'SAMEG307473';
my $group_name        = 'FAANG samples';
my $search_tag_field  = 'project';
my $search_tag_value  = 'FAANG';
my $biosample_api_key = undef;
my $mode              = 'report';
my $output_dir        = getcwd;
my $allow_removal     = undef;
my $help              = undef;
my $quiet             = undef;
my $paranoia          = undef;

GetOptions(
  "group_id=s"          => \$group_id,
  "group_name=s"        => \$group_name,
  "search_tag_field=s"  => \$search_tag_field,
  "search_tag_value=s"  => \$search_tag_value,
  "biosample_api_key=s" => \$biosample_api_key,
  "allow_removal"       => \$allow_removal,
  "mode=s"              => \$mode,
  "output_dir=s"        => \$output_dir,
  "help"                => \$help,
  "quiet"               => \$quiet,
  "paranoia"            => \$paranoia,
);

perldocs() if $help;

die "Need group ID and name" unless $group_id && $group_name;
die "Need search tag field and value"
  unless $search_tag_value && $search_tag_field;

die join( ' ', 'Set a valid mode from', @valid_modes )
  unless ( $mode && any { $_ eq $mode } @valid_modes );

die "Need a biosample api key for updates"
  if $mode eq 'update' && !$biosample_api_key;

if ( $mode eq 'update' || $mode eq 'dryrun' ) {
  die "Need an output dir" unless $output_dir && -w $output_dir;
  die "Need a writeable output dir" unless -w $output_dir;
}

#1. fetch sample IDs for group SAMEG307473
my $sample_ids_in_group = fetch_current_sample_ids_in_group($group_id);

#2. fetch all samples matching 'project: FAANG' (search by FAANG, check for having property 'project' with value ‘FAANG’ and were submitted directly to BioSamples)
my $project_sample_ids =
  fetch_sample_ids_matching_tag_and_value( $search_tag_field,
  $search_tag_value );

#3. get the disjoint between the two lists of ids - those to be added the group, those to be removed
my $commonality =
  fetch_common_and_disjoint( $sample_ids_in_group, $project_sample_ids );

if ( $mode eq 'report' ) {
  full_report($commonality);
}
elsif ( $mode eq 'dryrun' ) {
  dry_run( $commonality, );
}
elsif ( $mode eq 'update' ) {
  update($commonality);
}

sub full_report {
  my ($commonality) = @_;

  print_unless_quiet("Updates to $group_id:");
  report_changes( *STDOUT, $commonality );
  print_changes( *STDOUT, $commonality );
}

sub dry_run {
  my ($commonality) = @_;
  print_unless_quiet("Dry run mode. No changes will be made.");
  my $total_changes = report_changes( *STDOUT, $commonality );

  if ($total_changes) {
    my $filename = new_filename('dryrun.sampletab');
    write_sampletab( $commonality, $filename );
    my $st = slurp_file($filename);
    validate_slurped_sample_tab( $st, $filename );
    write_changes_file( $filename, $commonality );
  }
  else {
    print_unless_quiet("No changes to be made");
  }
  print_unless_quiet("Dry run completed successfully.");
}

sub update {
  my ($commonality) = @_;
  print_unless_quiet("Update mode. Changes will be made.");

  my $reporter_fh = $quiet ? undef : *STDOUT;
  my $total_changes = report_changes( $reporter_fh, $commonality );
  
  
  if ( $total_changes ) {
    my $filename = new_filename();
    write_sampletab( $commonality, $filename );
    my $st = slurp_file($filename);
    validate_slurped_sample_tab( $st, $filename );

    write_changes_file( $filename, $commonality );

    submit_slurped_sample_tab( $st, $filename );
  }
  else {
    print_unless_quiet("No changes to be made");
  }
  print_unless_quiet("Update completed successfully");
}

sub write_changes_file {
  my ( $filename, $commonality ) = @_;

  my $changes_file = $filename . '.changes';
  open( my $fh, '>', $changes_file );
  report_changes( $fh, $commonality );
  print_changes( $fh, $commonality );
  close($fh);
}

sub submit_slurped_sample_tab {
  my ( $st, $filename ) = @_;

  my $uri = 'http://www.ebi.ac.uk/biosamples/sampletab/api/v1/json/sb?apikey='
    . $biosample_api_key;

  my $req = HTTP::Request->new( 'POST', $uri );
  $req->header( 'Content-Type' => 'application/json;charset=UTF-8' );
  $req->content( encode_json { sampletab => $st } );

  my $lwp      = LWP::UserAgent->new;
  my $response = $lwp->request($req);

  if ( !$response->is_success ) {
    die
      "Submitting sample tab failed. File $filename and url $uri gave result "
      . $response->status_line;
  }

  if ($paranoia){
    open(my $fh,'>',$filename.'.biosample_response');
    print $fh $response->decoded_content;
    close $fh;
  }

  my $output       = decode_json $response->decoded_content;
  my $errors       = $output->{errors};
  my $st_corrected = $output->{sampletab};


  if ( !$errors ) {
    die
"Could not find 'errors' in submission response body from $uri, received this output:"
      . Dumper($output);
  }

  if (@$errors) {
    my @msg =
      (
"Errors received on submitting sample tab. File $filename and url $uri gave errors:"
      );
    push @msg, map { $_->{message} } @$errors;
    die join( $/, @msg );
  }
}

sub validate_slurped_sample_tab {
  my ( $st, $filename ) = @_;

  my $uri = 'http://www.ebi.ac.uk/biosamples/sampletab/api/v1/json/va';

  my $req = HTTP::Request->new( 'POST', $uri );
  $req->header( 'Content-Type' => 'application/json;charset=UTF-8' );
  $req->content( encode_json { sampletab => $st } );

  my $lwp      = LWP::UserAgent->new;
  my $response = $lwp->request($req);

  if ( !$response->is_success ) {
    die
      "Validating sample tab failed. File $filename and url $uri gave result "
      . $response->status_line;
  }

  my $output       = decode_json $response->decoded_content;
  my $errors       = $output->{errors};
  my $st_corrected = $output->{sampletab};

  if ( !$errors ) {
    die "Could not find 'errors' in validation response body from $uri";
  }

  if (@$errors) {
    my @msg =
      (
"Errors received on validating sample tab. File $filename and url $uri gave errors:"
      );
    push @msg, map { $_->{message} } @$errors;
    die join( $/, @msg );
  }
  return;    #TODO - take this out once there are some samples in the group
  my $c = new Data::Compare( $st, $st_corrected );
  my $identical = $c->Cmp;
  if ( !$identical ) {
    my $corrected_data_filename = "$filename.corrected";
    barf_file( $corrected_data_filename, $st_corrected );
    die
"SampleTab validation made corrections, but reported no errors. This implies that we're doing something wrong, so this script will exit. File $filename and url $uri produced the corrected data in $corrected_data_filename";
  }
}

sub slurp_file {
  my ($filename) = @_;

  my @d;

  open( my $fh, '<', $filename );

  while (<$fh>) {
    chomp;
    my @line = split /\t/;

    if ( !scalar(@line) ) {
      @line = ('');
    }

    push @d, \@line;
  }

  close $fh;
  return \@d;
}

sub barf_file {
  my ( $filename, $array_of_arrays ) = @_;

  open( my $fh, '>', $filename );

  for my $l (@$array_of_arrays) {
    print $fh join( "\t", @$l ) . $/;
  }

  close($fh);
}

sub new_filename {
  my ($suffix) = @_;
  $suffix //= 'sampletab';
  my $date = localtime->ymd('');

  my $fn;

  while ( !$fn || -e $fn ) {
    $fn = $output_dir.'/'.join( '.', $group_id, $date, substr( time, -5 ), $suffix );
  }

  return $fn;
}

sub write_sampletab {
  my ( $commonality, $filename ) = @_;

  open( my $fh, '>', $filename );

  my $date = localtime->ymd('/');

  my @sample_ids =
    ( @{ $commonality->{common_ids} }, @{ $commonality->{ids_to_add} } );
  if ( !$allow_removal ) {
    push @sample_ids, @{ $commonality->{ids_to_remove} };
  }

  print $fh <<"END";
[MSI]
Submission Title	FAANG - Functional Annotation of Animal Genomes
Submission Identifier	GSB-430
Submission Description	FAANG aims to produce comprehensive maps of functional elements in the genomes of domesticated animal species.
Submission Version	1.2
Submission Reference Layer	false
Submission Release Date	2017/01/01
Submission Update Date	$date
Organization Name	EMBL-EBI	FAANG
Organization Address	The European Bioinformatics Institute (EMBL-EBI), Wellcome Genome Campus, Hinxton, Cambridge, CB10 1SD, United Kingdom
Organization URI	http://www.ebi.ac.uk	http://faang.org/
Organization Email
Organization Role	EFO_0001731
Person Last Name	Richardson
Person Initials	M
Person First Name	David
Person Email	davidr\@ebi.ac.uk
Person Role	EFO_0001741
Publication PubMed ID 25854118

[SCD]
Sample Name	Sample Accession	Group Name	Group Accession
		$group_name	$group_id
END

  # BioSamples validation returns output with sorted scd lines
  # our submission should have the same ordering to simplify
  # interpretation of the validator output
  my @samples = sort {
    $a->property('Sample Name')->values->[0]
      cmp $b->property('Sample Name')->values->[0]
  } map { BioSD::fetch_sample($_) } @sample_ids;

  for my $s (@samples) {
    print $fh join( "\t",
      $s->property('Sample Name')->values->[0],
      $s->id, $group_name, $group_id )
      . $/;
  }

  close $fh;
}

sub print_changes {
  my ( $fh, $commonality ) = @_;

  for my $id ( @{ $commonality->{ids_to_add} } ) {
    print $fh "ADD\t$id$/";
  }

  my $rem_text = $allow_removal ? 'REMOVE' : 'COULD REMOVE';
  for my $id ( @{ $commonality->{ids_to_remove} } ) {
    print $fh "$rem_text\t$id$/";
  }

}

sub print_unless_quiet {
  my ($text) = @_;

  print $text. $/ unless $quiet;
}

sub report_changes {
  my ( $fh, $commonality ) = @_;

  my $ids_to_add_count    = scalar @{ $commonality->{ids_to_add} };
  my $ids_to_remove_count = scalar @{ $commonality->{ids_to_remove} };
  my $common_ids_count    = scalar @{ $commonality->{common_ids} };

  my $total_changes =
    $allow_removal
    ? ( $ids_to_add_count + $ids_to_remove_count )
    : $ids_to_add_count;
  my $removal = $allow_removal ? 'allowed' : 'disallowed';

  print $fh
"Found IDs to add: $ids_to_add_count; to remove ($removal): $ids_to_remove_count; unaffected: $common_ids_count; Total changes: $total_changes$/" if $fh;

  return $total_changes;
}

sub fetch_common_and_disjoint {
  my ( $sample_ids_in_group, $sample_ids_for_group ) = @_;

  my $lc = List::Compare->new(
    {
      lists    => [ $sample_ids_in_group, $sample_ids_for_group ],
      unsorted => 1,
    }
  );

  my @common_ids           = $lc->get_intersection();
  my @sample_ids_to_remove = $lc->get_Lonly;
  my @sample_ids_to_add    = $lc->get_Ronly;

  return {
    common_ids    => \@common_ids,
    ids_to_remove => \@sample_ids_to_remove,
    ids_to_add    => \@sample_ids_to_add,
  };
}

sub fetch_sample_ids_matching_tag_and_value {
  my ( $search_tag_field, $search_tag_value ) = @_;

  my $samples = BioSD::search_for_samples($search_tag_value);
  return [
    map { $_->id }
      grep {
      $_->property($search_tag_field)
        && defined $_->property($search_tag_field)->values
        && any { $_ eq $search_tag_value }
      @{ $_->property($search_tag_field)->values }

      } @$samples
  ];
}

sub fetch_current_sample_ids_in_group {
  my ($group_id) = @_;
  my $group = BioSD::fetch_group($group_id);
  die "Group $group_id was not found" unless $group;
  return $group->sample_ids;
}

sub perldocs {
  exec( 'perldoc', $0 );
  exit(0);
}
