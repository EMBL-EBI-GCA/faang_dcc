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

faang_dcc/scripts/sample_group_dumper.pl

=head1 SYNOPSIS

This script will search for BioSamples entries tagged "project: FAANG" and dump them as JSON or tsv

=head1 OPTIONS

  -help, binary flag to print out the perl docs
  -output_file <path>, path where output will be written
  -output_format <json|tsv>, how to format the output 
  -inherit_attributes, binary flag, should attributes be inherited via 'Derived from' relationships
  -json_source <json file>, use the json output of this script as the data source for this script - useful for multi step processing

  You probably don't want to change the following:
  -search_tag_field, which property should we check when searching for eligible samples. defaults to project
  -search_tag_value, what value should the tag field have if a sample is eligble. defaults to FAANG
  -col_sep string to separate columns in tsv, defaults to tab
  -line_sep string to separate lines in tsv, defaults to newline (\n)
  -value_sep string to separate values in tsv, where there are multiple values for a single header
  -empty_value string to use where a cell does not have a value in tsv, defaults to an empty string
  -elide_units units matching these values in this list will not be included in tsv output. By default YYYY-MM-DD, YYYY-MM and YYYY are elided, other units are included in value column

=cut

use strict;
use warnings;
use BioSD;
use List::Util qw(any);
use Data::Compare;
use Cwd;
use autodie;
use JSON;
use Data::Dumper;
use Getopt::Long;
use Carp;

my @valid_output_formats = qw(json tsv);
my $output_format_string = join( '|', @valid_output_formats );

my $search_tag_field = 'project';
my $search_tag_value = 'FAANG';
my $output_format    = 'json';
my $output;
my $inherit_attributes;
my $help;

my $col_sep     = "\t";
my $line_sep    = "\n";
my $value_sep   = ";";
my $empty_value = '';

my $cleanup_submission_dates = 1;
my $json_source;

my @elide_units = qw(YYYY YYYY-MM YYYY-MM-DD);

GetOptions(
  "search_tag_field=s"       => \$search_tag_field,
  "search_tag_value=s"       => \$search_tag_value,
  "output_format=s"          => \$output_format,
  "inherit_attributes"       => \$inherit_attributes,
  "output=s"                 => \$output,
  "col_sep=s"                => \$col_sep,
  "line_sep=s"               => \$line_sep,
  "value_sep=s"              => \$value_sep,
  "empty_value=s"            => \$empty_value,
  "cleanup_submission_dates" => \$cleanup_submission_dates,
  "elide_units=s"            => \@elide_units,
  "json_source=s"            => \$json_source,
  "help"                     => \$help,
);

perldocs() if $help;

croak "Need search_tag_field and search_tag_value"
  unless $search_tag_value && $search_tag_field;

croak "please specify -output_format $output_format_string"
  unless ( $output_format && any { $_ eq $output_format }
  @valid_output_formats );
croak "please specify -output <file>" if ( $output_format && !$output );

my $samples;
if ($json_source){
  $samples = load_from_json($json_source);
}
else {
  #1. fetch all samples matching 'project: FAANG' (search by FAANG, check for having property 'project' with value ‘FAANG’ and were submitted directly to BioSamples)
  #TODO use the sample group ID once it's working correctly.
  my $project_sample_ids =
    fetch_sample_ids_matching_tag_and_value( $search_tag_field,
    $search_tag_value );

  #2.

  $samples = convert_to_hashes( $project_sample_ids, $inherit_attributes );
}
cleanup_submission_dates( $samples ) if ($cleanup_submission_dates);


inherit_values( $samples ) if ($inherit_attributes);

my ( $fh, $close_fh );
if ( $output eq 'stdout' || $output eq '-' ) {
  $fh       = \*STDOUT;
  $close_fh = 0;
}
else {
  open( $fh, '>', $output );
  $close_fh = 1;
}

if ( $output_format eq 'tsv' ) {
  tsv_output( $samples, $fh );
}
if ( $output_format eq 'json' ) {
  json_output( $samples, $fh );
}

close($fh) if ($close_fh);

sub load_from_json {
  my ($file) = @_;
  
  my $x;
  my ($fh,$close_fh);
  
  if ($file eq '-' || $file eq 'stdin'){
    $fh = *STDIN;
  }
  else{
    open $fh, '<', $file;
    $close_fh = 1;
  }
  
  while (<$fh>){
    $x .= $_;
  }
  
  close $fh if $close_fh;
  
  my $samples = JSON->new->decode($x);
  
  return $samples;
}

sub inherit_values {
  my ($samples) = @_;

  my %samples_by_id = map { $_->{id} => $_ } @$samples;

  for my $s (@$samples) {
    next unless ( @{ $s->{derived_from} } );

    my @derived_sample_chain =
      derived_sample_chain( $s, { $s->{id} => 1 }, \%samples_by_id );

    merge_values_from_chain( $s, @derived_sample_chain );
  }

}

sub derived_sample_chain {
  my ( $sample, $sample_ids_seen, $samples_by_id ) = @_;

  my @sample_chain;

  for my $df_id ( @{ $sample->{derived_from} } ) {

    #avoid circular relationships
    next if exists $sample_ids_seen->{$df_id};
    $sample_ids_seen->{$df_id} = 1;

    my $sample_derived_from = $samples_by_id->{$df_id};
    push @sample_chain, $sample_derived_from;

    if ( @{ $sample_derived_from->{derived_from} } ) {
      push @sample_chain,
        derived_sample_chain( $sample_derived_from, $sample_ids_seen,
        $samples_by_id );
    }
  }

  return @sample_chain;
}

sub merge_values_from_chain {
  my ( $sample, @sample_chain ) = @_;

  my $target_properties = $sample->{properties};

  for my $source_sample (@sample_chain) {
    my $source_properties = $source_sample->{properties};

    for my $k ( keys %$source_properties ) {
      if ( !exists $target_properties->{$k} ) {
        $target_properties->{$k} = $source_properties->{$k};
      }
    }
  }
}

sub cleanup_submission_dates {
  my ($samples) = @_;

  for my $s (@$samples) {
    $s->{release_date} =~ s/T.*//;
    $s->{update_date}  =~ s/T.*//;
  }
}

sub json_output {
  my ( $samples, $fh ) = @_;

  my $json = JSON->new->pretty;

  print $fh $json->pretty->encode($samples);
}

sub tsv_output {
  my ( $samples, $fh ) = @_;

  my @fixed_s_headers = ( 'BioSamples ID', 'release date', 'update date' );
  my @fixed_p_headers =
    ( 'Sample Name', 'Sample Description', 'Material', 'Organism', 'Sex', );
  my @fixed_d_headers = ('Derived from');

  my %property_names;
  for my $s (@$samples) {
    map { $property_names{$_} = 1 } keys %{ $s->{properties} };
  }

  my %units_to_elide = map { $_ => 1 } @elide_units;

  my @dynamic_p_headers =
    dynamic_property_headers( $samples, \@fixed_p_headers );

  print $fh join( $col_sep,
    @fixed_s_headers,   @fixed_p_headers,
    @dynamic_p_headers, @fixed_d_headers )
    . $line_sep;

  for my $s (@$samples) {
    my @vals = ( $s->{id}, $s->{release_date}, $s->{update_date}, );

    for my $property_name ( @fixed_p_headers, @dynamic_p_headers ) {
      my $vals = $s->{properties}{$property_name};

      if ($vals) {
        my $v = join(
          $value_sep,
          map {
            $_->{value}
              . ( ( $_->{unit} && !$units_to_elide{ $_->{unit} } )
              ? ( ' ' . $_->{unit} )
              : '' )
          } @$vals
        );
        push @vals, $v // $empty_value;
      }
      else {
        push @vals, $empty_value;
      }
    }

    my $dv = join( $value_sep, @{ $s->{derived_from} } );
    push @vals, $dv // $empty_value;

    print $fh join( $col_sep, @vals ) . $line_sep;
  }

}

sub dynamic_property_headers {
  my ( $samples, $fixed_p_headers ) = @_;

  my %property_names;
  for my $s (@$samples) {
    map { $property_names{$_} = 1 } keys %{ $s->{properties} };
  }
  my %p_header_filter = map { $_ => 1 } ( @$fixed_p_headers, 'project' );

  my @dynamic_p_headers =
    sort { $a cmp $b } grep { !$p_header_filter{$_} } keys %property_names;

  return @dynamic_p_headers;
}

sub convert_to_hashes {
  my ( $sample_ids, $inherit_attributes ) = @_;
  my @samples;

  for my $sample_id (@$sample_ids) {

    my $sample = {
      id           => $sample_id,
      release_date => undef,
      update_date  => undef,
      annotations  => [],
      properties   => {},
      derived_from => []
    };
    push @samples, $sample;

    my $biosd_sample = BioSD::fetch_sample($sample_id);

    $sample->{release_date} = $biosd_sample->submission_release_date;
    $sample->{update_date}  = $biosd_sample->submission_update_date;

    #annotation
    my $biosd_annotation = $biosd_sample->annotations;
    for my $a (@$biosd_annotation) {
      push @{ $sample->{annotations} }, { type => $a->type };
    }

    #properties
    my $biosd_properties = $biosd_sample->properties;
    for my $p (@$biosd_properties) {
      my $prop_name = $p->class;
      my @qvalues;
      $sample->{properties}->{$prop_name} = \@qvalues;

      for my $qv ( @{ $p->qualified_values } ) {
        my $ts = $qv->term_source;
        my $q  = {
          value          => $qv->value,
          unit           => $qv->unit || undef,
          term_source    => ($ts) ? $ts->name : undef,
          term_source_id => ($ts) ? $ts->term_source_id : undef,
        };

        push @qvalues, $q;
      }
    }

    #derived from
    my $biosd_derived_from = $biosd_sample->derived_from;
    for my $df_sample (@$biosd_derived_from) {
      push @{ $sample->{derived_from} }, $df_sample->id;
    }

  }
  
  @samples = sort { $a->{id} cmp $b->{id} } @samples;
  
  return \@samples;
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

sub perldocs {
  exec( 'perldoc', $0 );
  exit(0);
}
