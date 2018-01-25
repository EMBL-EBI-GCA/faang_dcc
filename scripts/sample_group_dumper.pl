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

This script will search for BioSamples entries and dump information to JSON or TSV

=head1 OPTIONS

=head2 SOURCE DATA

Use either -sample_group_id, -search_tag_field and -search_tag_value, or -json_source

  -sample_group_id, BioSamples group id to fetch samples from
  -search_tag_field, which property should we check when searching for eligible samples. defaults to project
  -search_tag_value, what value should the tag field have if a sample is eligble. defaults to FAANG
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
use List::Util qw(any none);
use Data::Compare;
use Cwd;
use autodie;
use WWW::Mechanize;
use JSON -support_by_pp;
use Data::Dumper;
use List::Uniq qw(uniq);
use Getopt::Long;
use Carp;
use Bio::Metadata::Validate::Support::BioSDLookup;

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

my $cleanup_submission_dates = 1;
my $inherit_attributes;

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
  "cleanup_submission_dates" => \$cleanup_submission_dates,
  "inherit_attributes"       => \$inherit_attributes,
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

$source_options++ if ( $search_tag_value && $search_tag_field );
$source_options++ if ($json_source);
$source_options++ if ($sample_group_id);
$source_options++ if ($got_rst_args);

croak
"Need a source of sample information, specify either -sample_group_id, -search_tag_field and -search_tag_value, -json_source, or all of the following: -dbhost -dbuser -dbpass  -dbport -dbname "
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

my $samples;

#section 1, in which we shall find some samples

if ($json_source) {
  $samples = load_from_json($json_source);
}
else {
  my $project_sample_ids;

  if ($sample_group_id) {
    $project_sample_ids = fetch_sample_ids_in_group($sample_group_id);
  }
  elsif ( defined $search_tag_field && defined $search_tag_value ) {
    $project_sample_ids =
      fetch_sample_ids_matching_tag_and_value( $search_tag_field,
      $search_tag_value );
  }
  elsif ($rst) {
    $project_sample_ids = fetch_biosample_ids_from_rst($rst);
  }

  $samples = biosample_ids_to_entities($project_sample_ids);
}

#section 2, in which we may fiddle around with the data

cleanup_submission_dates($samples) if ($cleanup_submission_dates);

validate_samples( $samples, $validator ) if ($validator);

inherit_values($samples) if ($inherit_attributes);

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
    $samples, $fh,
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
  json_output( $samples, $fh, $pretty_json, $json_format );
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

  my $sample_hashes = JSON->new->decode($x);

  if ( ref $sample_hashes eq 'HASH' ) {
    my @h = values %$sample_hashes;
    $sample_hashes = \@h;
  }

  my @samples = map { Bio::Metadata::Entity->new($_) } @$sample_hashes;

  return \@samples;
}

sub inherit_values {
  my ($samples) = @_;

  my %samples_by_id = map { $_->id() => $_ } @$samples;

  for my $s (@$samples) {

    #    next unless ( @{ $s->{derived_from} } );

    my @derived_sample_chain =
      derived_sample_chain( $s, { $s->id() => 1 }, \%samples_by_id );

    merge_values_from_chain( $s, @derived_sample_chain );
  }

}

sub get_derived_from_ids {
  my ($sample) = @_;

  return map { $_->value }
    grep { lc( $_->name ) eq 'derived from' } $sample->all_attributes;
}

sub derived_sample_chain {
  my ( $sample, $sample_ids_seen, $samples_by_id ) = @_;

  my @sample_chain;

  for my $df_id ( get_derived_from_ids($sample) ) {

    #avoid circular relationships
    next if exists $sample_ids_seen->{$df_id};
    $sample_ids_seen->{$df_id} = 1;

    my $sample_derived_from = $samples_by_id->{$df_id};

    if ( !$sample_derived_from ) {
	  my $dss = biosample_ids_to_entities([$df_id]);
      ($sample_derived_from) = @$dss;
    }

    push @sample_chain, $sample_derived_from;

    push @sample_chain,
      derived_sample_chain( $sample_derived_from, $sample_ids_seen,
      $samples_by_id );

  }

  return @sample_chain;
}

sub merge_values_from_chain {
  my ( $sample, @sample_chain ) = @_;

  my $target_properties = $sample->organised_attr;
  my $validation_status;

  if ( $target_properties->{$validation_status_attribute_name} ) {
    ($validation_status) =
      @{ $target_properties->{$validation_status_attribute_name} };
  }

  for my $source_sample (@sample_chain) {
    my $source_properties = $source_sample->organised_attr;

    for my $k (
      grep { !exists $target_properties->{$_} }
      keys %$source_properties
      )
    {
      $target_properties->{$k} = $source_properties->{$k};
      $sample->add_attribute( @{ $source_properties->{$k} } );
      ($validation_status) = @{ $source_properties->{$k} }
        if ( $k eq $validation_status_attribute_name );
    }

    if ( $validation_status
      && $source_properties->{$validation_status_attribute_name} )
    {
      my ($chained_status) =
        @{ $source_properties->{$validation_status_attribute_name} };

      my $take_status = 0;

      #preserve the worst value in the chain
      if ( $chained_status->value eq 'error'
        && $validation_status->value ne 'error' )
      {
        $take_status = 1;
      }
      if ( $chained_status->value eq 'warning'
        && $validation_status->value eq 'pass' )
      {
        $take_status = 1;
      }

      if ($take_status) {
        $validation_status->value( $chained_status->value );
      }

    }
  }
}

sub cleanup_submission_dates {
  my ($samples) = @_;

  for my $s (@$samples) {
    my $oa = $s->organised_attr();

    for my $k ( 'biosamples release date', 'biosamples update date' ) {
      my $attrs = $oa->{$k};

      if ($attrs) {
        for my $a (@$attrs) {
          my $v = $a->value;
          $v =~ s/T.*//;
          $a->value($v);
        }

      }
    }
  }
}

sub json_output {
  my ( $samples, $fh, $pretty_json, $json_format ) = @_;

  my $json = JSON->new;

  if ($pretty_json) {
    $json = $json->pretty;
  }

  my $data;

  if ( $json_format eq 'array' ) {
    $data = [ map { $_->to_hash } @$samples ];
  }
  elsif ( $json_format eq 'hash' ) {
    my %d = map { $_->id => $_->to_hash } @$samples;
    $data = \%d;
  }
  else {
    croak "Not a recognised json_format: $json_format";
  }
  print $fh $json->encode($data);
}

sub tsv_output {
  my ( $samples, $fh, $f, ) = @_;

  my $col_sep                = $f->{col_sep};
  my $lin_sep                = $f->{line_sep};
  my $value_sep              = $f->{value_sep};
  my $empty_value            = $f->{empty_value};
  my $omit_units             = $f->{omit_units};
  my $property_columns       = $f->{property_columns};
  my $show_validation_status = $f->{show_validation_status};

  my @fixed_s_headers = ( 'BioSamples ID', );
  my @fixed_d_headers = ('Derived from');

  my @p_headers;

  if ( $property_columns && @$property_columns ) {
    @p_headers = @$property_columns;
  }
  else {
    my @fixed_p_headers = (
      'BioSamples release date',
      'BioSamples update date',
      'Sample Name',
      'Sample Description',
      'Material',
      'Organism',
      'Sex',
    );
    unshift @fixed_p_headers, $validation_status_attribute_name
      if ($show_validation_status);

    my @dynamic_p_headers =
      dynamic_property_headers( $samples, \@fixed_p_headers );

    @p_headers = ( @fixed_p_headers, @dynamic_p_headers );
  }

  my %property_names;
  for my $s (@$samples) {
    
    map { $property_names{$_} = 1 } keys %{ $s->{properties} };
  }

  my %units_to_omit = map { $_ => 1 } @$omit_units;

  print $fh join( $col_sep, @fixed_s_headers, @p_headers, @fixed_d_headers )
    . $line_sep;

  for my $s (@$samples) {
    my $organised_attrs = $s->organised_attr();

    my @vals = ( $s->id );

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

    my $dv = join( $value_sep,
      map { $_->value } @{ $organised_attrs->{'derived from'} } );
    push @vals, $dv // $empty_value;

    print $fh join( $col_sep, @vals ) . $line_sep;
  }

}

sub dynamic_property_headers {
  my ( $samples, $fixed_p_headers ) = @_;

  my %property_names;
  my $empty_entity = Bio::Metadata::Entity->new();

  for my $s (@$samples) {
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

sub biosample_ids_to_entities {
  my ( $sample_ids, $inherit_attributes ) = @_; 
  my @samples;
  for my $sample_id (@$sample_ids) {
    my $url = "https://www.ebi.ac.uk/biosamples/api/samples/".$sample_id;
    my $biosd_lookup = fetch_biosample_json($url);
    if (!$biosd_lookup){
      carp "No biosample entry for $sample_id";#TODO - should this croak?
      next;
    }
    my $entity = Bio::Metadata::Entity->new($biosd_lookup);
    push @samples, $entity;    
    
    $entity->add_attribute( { name => 'Sample Name', value => $biosd_lookup->{accession} } );
    $entity->id($sample_id);
    my $sample = $biosd_lookup;
  }
  @samples = sort { $a->{id} cmp $b->{id} } @samples;
  return \@samples;
}

sub fetch_sample_ids_matching_tag_and_value {
  my ( $search_tag_field, $search_tag_value ) = @_;
  my $url = "https://www.ebi.ac.uk/biosamples/samples?filter=attr%3A".$search_tag_field."%3A".$search_tag_value;
  my @pages = fetch_biosamples_json($url);
  my @samples;
  foreach my $page (@pages){
    foreach my $sample (@{$page->{samples}}){
      push(@samples, $sample->{accession});
    }
  }
  return \@samples;
}

sub fetch_sample_ids_in_group {
  my ($group_id) = @_;
  my $url = "https://www.ebi.ac.uk/biosamples/api/groups/.$group_id";
  my @pages = fetch_biosamples_json($url);
  confess "Group $group_id was not found" unless @pages;
  my @samples;
  foreach my $page (@pages){
    foreach my $samplegroup (@{$page->{groups}}){
      foreach my $sample (@{$samplegroup->{samples}}){
        push(@samples, $sample);
      }
    }
  }
  return \@samples;
}

sub fetch_biosample_ids_from_rst {
  my ($rst)   = @_;
  my $sa      = $rst->get_SampleAdaptor;
  my $samples = $sa->fetch_all();
  my @biosample_ids = grep { defined $_ } map { $_->biosample_id } @$samples;
  return \@biosample_ids;
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

sub validate_samples {
  my ( $samples, $validator ) = @_;

  my (
    $entity_status,      $entity_outcomes, $attribute_status,
    $attribute_outcomes, $entity_rule_groups,
  ) = $validator->check_all($samples);

  for my $s (@$samples) {
    my $v = $entity_status->{$s};
    $s->add_attribute(
      { name => $validation_status_attribute_name, value => $v } );
  }

}

sub fetch_biosamples_json{
  my ($json_url) = @_;

  my $browser = WWW::Mechanize->new();
  $browser->get( $json_url );
  my $content = $browser->content();
  my $json = new JSON;
  my $json_text = $json->decode($content);
  
  my @pages;
  foreach my $item ($json_text->{_embedded}){ #Store page 0
    push(@pages, $item);
  }
  
  while ($$json_text{_links}{next}{href}){  # Iterate until no more pages using HAL links
    $browser->get( $$json_text{_links}{next}{href});  # Get next page
    $content = $browser->content();
    $json_text = $json->decode($content);
    foreach my $item ($json_text->{_embedded}){
      push(@pages, $item);  # Store each additional page
    }
  }
  return @pages;
}

sub fetch_biosample_json{
  my ($json_url) = @_;

  my $browser = WWW::Mechanize->new();
  $browser->get( $json_url );
  my $content = $browser->content();
  my $json = new JSON;
  my $json_text = $json->decode($content);
  return $json_text;
}

sub fetch_relations_json{
  my ($json_url) = @_;

  my $browser = WWW::Mechanize->new();
  $browser->get( $json_url );
  my $content = $browser->content();
  my $json = new JSON;
  my $json_text = $json->decode($content);
  return $json_text;
}