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

faang_dcc/scripts/experiment_data_dumper.pl

=head1 SYNOPSIS

This script will search for experiment entries and dump information to JSON or TSV

=head1 OPTIONS

=head2 SOURCE DATA

Use either a reseq track db, or -json_source

  -json_source <json file>, use the json output of this script as the data source for this script - useful for multi step processing


=head2 OUTPUT

  -output_file <path>, path where output will be written
  -output_format <json|tsv>, how to format the output 

=head2 TSV formatting

  -col_sep string to separate columns in tsv, defaults to tab
  -line_sep string to separate lines in tsv, defaults to newline (\n)
  -value_sep string to separate values in tsv, where there are multiple values for a single header
  -empty_value string to use where a cell does not have a value in tsv, defaults to an empty string
  -omit_units units matching these values in this list will not be included in tsv output. By default YYYY-MM-DD, YYYY-MM and YYYY are omited, other units are included in value column
  -tsv_column, column to use in output
  -tsv_column_file, file containing a list of columns to use in output


=head2 JSON formating

  -pretty_json, boolean flag, make the json more human readable 

=head2 DATA PROCESSING

  -inherit_attributes, boolean flag, should attributes be inherited via 'Derived from' relationships
  -cleanup_submission_dates, boolean flag, should we strip the time from submission release and update fields

=head2 MISC

  -help, boolean flag to print out the perl docs

=cut

use strict;
use warnings;
use Bio::Metadata::Entity;
use Bio::Metadata::Attribute;
use List::Util qw(any none);
use Data::Compare;
use Cwd;
use autodie;
use JSON;
use Data::Dumper;
use Getopt::Long;
use Carp;

my $validation_status_attribute_name = 'Metadata validation status';

my @valid_output_formats = qw(json tsv);
my @valid_json_formats   = qw(hash array);
my $output_format_string = join( '|', @valid_output_formats );
my $json_format_string   = join( '|', @valid_json_formats );

my $output_format = 'json';
my $output;
my $search_tag_field;
my $search_tag_value;
my $json_source;
my $sample_group_id;

my $col_sep     = "\t";
my $line_sep    = "\n";
my $value_sep   = ";";
my $empty_value = '';
my @omit_units  = qw(YYYY YYYY-MM YYYY-MM-DD);
my @tsv_columns;
my $tsv_column_file;
my %rst_db;

my $pretty_json;
my $json_format = 'array';

my $validation_rules_file;

my $help;

GetOptions(

  #source
  "json_source=s"      => \$json_source,
  "search_tag_field=s" => \$search_tag_field,
  "search_tag_value=s" => \$search_tag_value,
  "sample_group_id=s"  => \$sample_group_id,

  "dbhost=s" => \$rst_db{-host},
  "dbuser=s" => \$rst_db{-user},
  "dbpass=s" => \$rst_db{-pass},
  "dbport=s" => \$rst_db{-port},
  "dbname=s" => \$rst_db{-dbname},

  #output
  "output_format=s" => \$output_format,
  "output=s"        => \$output,

  #tsv specific output
  "col_sep=s"         => \$col_sep,
  "line_sep=s"        => \$line_sep,
  "value_sep=s"       => \$value_sep,
  "empty_value=s"     => \$empty_value,
  "units_to_omit=s"   => \@omit_units,
  "tsv_column=s"      => \@tsv_columns,
  "tsv_column_file=s" => \$tsv_column_file,

  #json specific output
  "pretty_json"   => \$pretty_json,
  "json_format=s" => \$json_format,

  #processing
  "validation_rules_file=s"  => \$validation_rules_file,

  #misc
  "help" => \$help,
) || croak "Unexpected arguments: $!";

perldocs() if $help;

my $got_rst_args =
  (    defined $rst_db{-host}
    && defined $rst_db{-user}
    && defined $rst_db{-pass}
    && defined $rst_db{-port}
    && defined $rst_db{-dbname} );

my $source_options = 0;

$source_options++ if ($json_source);
$source_options++ if ($got_rst_args);

croak
"Need a source of sample information, specify either -json_source, or all of the following: -dbhost -dbuser -dbpass  -dbport -dbname "
  unless ( $source_options == 1 );

croak "please specify -output_format $output_format_string"
  unless ( $output_format && any { $_ eq $output_format }
  @valid_output_formats );
croak "please specify -output <file>" if ( $output_format && !$output );
croak "please specify -json_format $json_format_string"
  unless ( $json_format && any { $json_format eq $_ } @valid_json_formats );

my $validator;
$validator = create_validator($validation_rules_file)
  if ($validation_rules_file);

my $rst;
if ($got_rst_args) {
  require ReseqTrack::DBSQL::DBAdaptor;

  $rst = ReseqTrack::DBSQL::DBAdaptor->new(%rst_db);

  croak "could not connect to reseqtrack db" unless ($rst);
}

@tsv_columns = load_tsv_columns($tsv_column_file) if ($tsv_column_file);

my $experiments;

#section 1, in which we shall find some samples

if ($json_source) {
  $experiments = load_from_json($json_source);
}
else {
  $experiments = [];

  my $ea = $rst->get_ExperimentAdaptor;

  for my $exp ( @{ $ea->fetch_all() } ) {
    my @attributes =
      map { { name => $_->attribute_name, value => $_->attribute_value, unit => $_->attribute_units } }
      @{ $exp->attributes };

    my $ent = Bio::Metadata::Entity->new(
      id         => $exp->experiment_source_id,
      attributes => \@attributes
    );
    $ent->add_link( Bio::Metadata::Entity->new(id => $exp->sample->biosample_id, type => 'sample') );

    push @$experiments, $ent;
  }

}

#section 2, in which we may fiddle around with the data

validate_experiments( $experiments, $validator ) if ($validator);

#section 3, in which we output

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
  tsv_output(
    $experiments,
    $fh,
    {
      col_sep                => $col_sep,
      line_sep               => $line_sep,
      value_sep              => $value_sep,
      empty_value            => $empty_value,
      omit_units             => \@omit_units,
      property_columns       => \@tsv_columns,
      show_validation_status => ( defined $validator ),
    }
  );
}
if ( $output_format eq 'json' ) {
  json_output( $experiments, $fh, $pretty_json, $json_format );
}

close($fh) if ($close_fh);

sub load_from_json {
  my ($file) = @_;

  my $x;
  my ( $fh, $close_fh );

  if ( $file eq '-' || $file eq 'stdin' ) {
    $fh = *STDIN;
  }
  else {
    open $fh, '<', $file;
    $close_fh = 1;
  }

  while (<$fh>) {
    $x .= $_;
  }

  close $fh if $close_fh;

  my $experiment_hashes = JSON->new->decode($x);

  if ( ref $experiment_hashes eq 'HASH' ) {
    my @h = values %$experiment_hashes;
    $experiment_hashes = \@h;
  }

  my @experiments = map { Bio::Metadata::Entity->new($_) } @$experiment_hashes;

  return \@experiments;
}

sub json_output {
  my ( $experiment, $fh, $pretty_json, $json_format ) = @_;

  my $json = JSON->new;

  if ($pretty_json) {
    $json = $json->pretty;
  }

  my $data;

  if ( $json_format eq 'array' ) {
    $data = [ map { $_->to_hash } @$experiment ];
  }
  elsif ( $json_format eq 'hash' ) {
    my %d = map { $_->id => $_->to_hash } @$experiment;
    $data = \%d;
  }
  else {
    croak "Not a recognised json_format: $json_format";
  }
  print $fh $json->encode($data);
}

sub tsv_output {
  my ( $experiments, $fh, $f, ) = @_;

  my $col_sep                = $f->{col_sep};
  my $lin_sep                = $f->{line_sep};
  my $value_sep              = $f->{value_sep};
  my $empty_value            = $f->{empty_value};
  my $omit_units             = $f->{omit_units};
  my $property_columns       = $f->{property_columns};
  my $show_validation_status = $f->{show_validation_status};

  my @fixed_s_headers = ( 'Experiment ID', 'Sample ID');
  my @fixed_d_headers = ();

  my @p_headers;

  if ( $property_columns && @$property_columns ) {
    @p_headers = @$property_columns;
  }
  else {
    my @fixed_p_headers = (
      
    );
    unshift @fixed_p_headers, $validation_status_attribute_name
      if ($show_validation_status);

    my @dynamic_p_headers =
      dynamic_property_headers( $experiments, \@fixed_p_headers );

    @p_headers = ( @fixed_p_headers, @dynamic_p_headers );
  }



  my %units_to_omit = map { $_ => 1 } @$omit_units;

  print $fh join( $col_sep, @fixed_s_headers, @p_headers, @fixed_d_headers )
    . $line_sep;

  for my $e (@$experiments) {
    my $organised_attrs = $e->organised_attr();
    my ($sample) = @{$e->links};

    my @vals = ( $e->id, $sample->id);

    for my $property_name (@p_headers) {
      my $vals = $organised_attrs->{ lc($property_name) };

      if ($vals) {
        my $v = join(
          $value_sep,
          map {
            $_->value
              . (
                ( $_->units && !$units_to_omit{ $_->units } )
              ? ( ' ' . $_->units )
              : ''
              )
          } @$vals
        );
        push @vals, $v // $empty_value;
      }
      else {
        push @vals, $empty_value;
      }
    }
    
    print $fh join( $col_sep, @vals ) . $line_sep;
  }

}

sub dynamic_property_headers {
  my ( $experiments, $fixed_p_headers ) = @_;

  my %property_names;
  my $empty_entity = Bio::Metadata::Entity->new();

  for my $s (@$experiments) {
    map { $property_names{$_} = 1 }
      map { $empty_entity->normalise_attribute_name( $_->name ) }
      $s->all_attributes;
  }

  my %p_header_filter =
    map { $empty_entity->normalise_attribute_name($_) => 1 }
    (@$fixed_p_headers);

  my @dynamic_p_headers =
    sort { $a cmp $b } grep { !$p_header_filter{$_} } keys %property_names;

  return @dynamic_p_headers;
}

sub load_tsv_columns {
  my ($tsv_column_file) = @_;

  my @tsv_columns;
  open my $fh, '<', $tsv_column_file;
  while (<$fh>) {
    chomp;
    push @tsv_columns, split /\t/;
  }

  close $fh;

  return @tsv_columns;
}

sub perldocs {
  exec( 'perldoc', $0 );
  exit(0);
}

sub create_validator {
  my ( $rule_file, $verbose ) = @_;

  require Bio::Metadata::Loader::JSONRuleSetLoader;
  require Bio::Metadata::Validate::EntityValidator;

  my $loader = Bio::Metadata::Loader::JSONRuleSetLoader->new();
  print "Attempting to load $rule_file$/" if $verbose;
  my $rule_set = $loader->load($rule_file);
  print 'Loaded ' . $rule_set->name . $/ if $verbose;

  my $validator =
    Bio::Metadata::Validate::EntityValidator->new( rule_set => $rule_set );

  return $validator;
}

sub validate_experiments {
  my ( $experiments, $validator ) = @_;

  my (
    $entity_status,      $entity_outcomes, $attribute_status,
    $attribute_outcomes, $entity_rule_groups,
  ) = $validator->check_all($experiments);

  for my $e (@$experiments) {
    my $v = $entity_status->{$e};
    $e->add_attribute(
      { name => $validation_status_attribute_name, value => $v } );
  }

}
