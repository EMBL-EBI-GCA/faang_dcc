package ReseqTrack::Hive::PipeSeed::FaangErsaDump;

use strict;
use warnings;
use ReseqTrack::Tools::Exception qw(throw);
use List::Util qw(any none);
use base ('ReseqTrack::Hive::PipeSeed::CollectionFiles');

sub create_seed_params {
  my ($self) = @_;

  throw(
    'this module will only accept pipelines that work on the collection table')
    if $self->table_name ne 'collection';

  my $options = $self->options;

  my $db = $self->db();
  my $ra = $db->get_RunAdaptor;

  my %run_conditions = (
    adaptor            => $ra,
    output_columns     => $self->option_array('output_run_columns'),
    output_attributes  => $self->option_array('output_run_attributes'),
    require_attributes => $options->{'require_run_attributes'} || {},
    exclude_attributes => $options->{'exclude_run_attributes'} || {},
    require_columns    => $options->{'require_run_columns'} || {},
    exclude_columns    => $options->{'exclude_run_columns'} || {},
  );

  my %experiment_conditions = (
    adaptor            => $db->get_ExperimentAdaptor,
    output_columns     => $self->option_array('output_experiment_columns'),
    output_attributes  => $self->option_array('output_experiment_attributes'),
    require_attributes => $options->{'require_experiment_attributes'} || {},
    exclude_attributes => $options->{'exclude_experiment_attributes'} || {},
    require_columns    => $options->{'require_experiment_columns'} || {},
    exclude_columns    => $options->{'exclude_experiment_columns'} || {},
  );

  my %sample_conditions = (
    adaptor            => $db->get_SampleAdaptor,
    output_columns     => $self->option_array('output_sample_columns'),
    output_attributes  => $self->option_array('output_sample_attributes'),
    require_attributes => $options->{'require_sample_attributes'} || {},
    exclude_attributes => $options->{'exclude_sample_attributes'} || {},
    require_columns    => $options->{'require_sample_columns'} || {},
    exclude_columns    => $options->{'exclude_sample_columns'} || {},
  );

  my %study_conditions = (
    adaptor            => $db->get_StudyAdaptor,
    output_columns     => $self->option_array('output_study_columns'),
    output_attributes  => $self->option_array('output_study_attributes'),
    require_attributes => $options->{'require_study_attributes'} || {},
    exclude_attributes => $options->{'exclude_study_attributes'} || {},
    require_columns    => $options->{'require_study_columns'} || {},
    exclude_columns    => $options->{'exclude_study_columns'} || {},
  );

  $self->SUPER::create_seed_params();

  my $received_seed_params = $self->seed_params;
  my @approved_seed_params;
  $self->seed_params( \@approved_seed_params );

SEED:
  for my $seed_params (@$received_seed_params) {
    my ( $collection, $output_hash ) = @$seed_params;

    #get objects
    my $run = $ra->fetch_by_source_id( $collection->name );

    throw( "Cannot find run for collection with name " . $collection->name )
      unless ($run);

    my $experiment = $run->experiment();
    my $sample     = $experiment->sample();
    my $study      = $experiment->study();

    #output
    my $match = $self->filter_and_update_output(
      output_hash => $output_hash,
      object      => $run,
      %run_conditions
    );
    next SEED unless $match;
    $match = $self->filter_and_update_output(
      output_hash => $output_hash,
      object      => $experiment,
      %experiment_conditions
    );

    next SEED unless $match;
    $match = $self->filter_and_update_output(
      output_hash => $output_hash,
      object      => $sample,
      %sample_conditions
    );

    next SEED unless $match;
    $match = $self->filter_and_update_output(
      output_hash => $output_hash,
      object      => $study,
      %study_conditions
    );
    next SEED unless $match;

    if ($match) {
      push @approved_seed_params, $seed_params;
    }

  }
}

sub filter_and_update_output {
  my ( $self, %p ) = @_;

  #return 1 if object matches filter conditions, undef otherwise
  #only works for object with an adaptor based on LazyAdaptor
  my $object             = $p{object};
  my $output_hash        = $p{output_hash};
  my $adaptor            = $p{adaptor};
  my $output_columns     = $p{output_columns};
  my $output_attributes  = $p{output_attributes};
  my $require_attributes = $p{require_attributes};
  my $exclude_attributes = $p{exclude_attributes};
  my $require_columns    = $p{require_columns};
  my $exclude_columns    = $p{exclude_columns};

  my $attributes      = $object->attributes;
  my $column_mappings = $adaptor->column_mappings($object);

  #filter columns
  #require
  for my $column_name ( keys %$require_attributes ) {
    throw( "no column mapping for $column_name from " . ref($adaptor) )
      unless $column_mappings->{$column_name};
    my $match_values = $require_attributes->{$column_name};
    my $value        = &{ $column_mappings->{$column_name} }();
    return undef if none { $value eq $_ } @$match_values;
  }

  #exclude
  for my $column_name ( keys %$exclude_attributes ) {
    throw( "no column mapping for $column_name from " . ref($adaptor) )
      unless $column_mappings->{$column_name};
    my $match_values = $exclude_attributes->{$column_name};
    my $value        = &{ $column_mappings->{$column_name} }();
    return undef if any { $value eq $_ } @$match_values;
  }

  #filter attributes
  #require
  for my $attribute_name ( keys %$require_attributes ) {
    my $match_values = $require_attributes->{$attribute_name};
    my ($attribute) =
      grep { $_->attribute_name eq $attribute_name } @$attributes;
    my $value = $attribute->value;

    return undef if ( !$attribute || none { $value eq $_ } @$match_values );
  }

  #exclude
  for my $attribute_name ( keys %$exclude_attributes ) {
    my $match_values = $exclude_attributes->{$attribute_name};
    my ($attribute) =
      grep { $_->attribute_name eq $attribute_name } @$attributes;
    my $value = $attribute->value;

    return undef if ( $attribute && any { $value eq $_ } @$match_values );
  }

  #output
  #output columns
  for my $column_name (@$output_columns) {
    throw( "no column mapping for $column_name from " . ref($adaptor) )
      unless $column_mappings->{$column_name};
    my $value = &{ $column_mappings->{$column_name} }();
    $output_hash->{$column_name} = $value;

  }

  #output attributes

  for my $attribute_name (@$output_attributes) {
    my ($attribute) =
      grep { $_->attribute_name eq $attribute_name } @$attributes;
    if ($attribute) {
      $output_hash->{$attribute_name} = $attribute->attribute_value;
    }
  }

  return 1;
}

1;
