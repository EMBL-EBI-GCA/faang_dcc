package ReseqTrack::Hive::PipeSeed::FaangErsaDump;

use strict;
use warnings;
use ReseqTrack::Tools::Exception qw(throw);
use List::Util qw(any none first);
use autodie;
use JSON::MaybeXS;
use base ('ReseqTrack::Hive::PipeSeed::CollectionFiles');
use Data::Dumper;
use Bio::Metadata::Entity;

sub create_seed_params {
  my ($self) = @_;

  throw(
    'this module will only accept pipelines that work on the collection table')
    if $self->table_name ne 'collection';

  my $options = $self->options;

  my $db = $self->db();
  my $ra = $db->get_RunAdaptor;

  my $output_parameter_name = $options->{'output_parameter_name'}
    || 'ersa_dump';

  my $input_run_id_lookups = $self->load_run_input_lookup();
  my $biosample_entities_by_id =
    $self->load_entities_from_file( $options->{biosample_data_file} );
  my $experiment_entities_by_id =
    $self->load_entities_from_file( $options->{experiment_data_file} );

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

  my %biosample_conditions = (
    output_attributes  => $self->option_array('output_biosample_attributes'),
    require_attributes => $options->{'require_biosample_attributes'} || {},
    exclude_attributes => $options->{'exclude_biosample_attributes'} || {},
  );

  $self->SUPER::create_seed_params();

  my $received_seed_params = $self->seed_params;
  my @approved_seed_params;

SEED:
  for my $seed_params (@$received_seed_params) {
    my ( $collection, $output_hash ) = @$seed_params;

    my $run_source_id = $collection->name;

    #get objects

    my $run = $ra->fetch_by_source_id($run_source_id);

    throw( "Cannot find run for collection with name " . $collection->name )
      unless ($run);

    my $experiment = $run->experiment();
    my $sample     = $experiment->sample();
    my $study      = $experiment->study();

    my $biosample_id = $sample->biosample_id;
    my $biosample    = $biosample_entities_by_id->{ $sample->biosample_id };

    my $experiment_entity =
      $experiment_entities_by_id->{ $experiment->experiment_source_id };

    next SEED unless $biosample;    #TODO temp fix while testing
    throw( "Cannot find biosample entry $biosample_id for sample "
        . $sample->sample_source_id )
      unless $biosample;

    my $match = 1;

    $match = $self->filter_by_entity_validated_metadata($experiment_entity);
    next SEED unless $match;

    $match = $self->filter_by_entity_validated_metadata($biosample)
      if $biosample;
#    next SEED unless $match;

    $match =
      $self->filter_and_update_for_chip_control( $run, $experiment,
      $input_run_id_lookups, $output_hash );
#    next SEED unless $match;

    $match = $self->filter_and_update_output_by_biosample(
      output_hash => $output_hash,
      biosample   => $biosample,
      %biosample_conditions
    );
    next SEED unless $match;

    $match = $self->filter_and_update_output(
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
      $self->rewrite_output_hash( $output_parameter_name, $output_hash )
        if $output_parameter_name;
      push @approved_seed_params, $seed_params;
    }

  }
  $self->seed_params( \@approved_seed_params );

}

sub rewrite_output_hash {
  my ( $self, $output_parameter_name, $output_hash ) = @_;

  my %cloned_hash = %$output_hash;

  for my $k ( keys %$output_hash ) {
    delete $output_hash->{$k};
  }

  $output_hash->{$output_parameter_name} = \%cloned_hash;

}

sub load_json {
  my ( $self, $src_file ) = @_;

  open my $fh, '<', $src_file;

  my $buffer;
  {
    local $/ = undef;
    $buffer = <$fh>;
  }
  close $fh;
  return decode_json $buffer;
}

sub load_run_input_lookup {
  my ($self) = @_;

  my @lookup_hashes;

  my $srcs = $self->options()->{run_input_lookup_files};

  for my $src_file (@$srcs) {
    push @lookup_hashes, $self->load_json($src_file);
  }

  return \@lookup_hashes;
}

sub load_entities_from_file {
  my ( $self, $src_file ) = @_;

  my $data = $self->load_json($src_file);

  throw("json sample file $src_file should decode to an array")
    if ( !$data || !ref $data || ref $data ne 'ARRAY' );

  my %entities_by_id =
    map { $_->id() => $_ }
    map { Bio::Metadata::Entity->new($_) } @$data;

  return \%entities_by_id;
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
  for my $column_name ( keys %$require_columns ) {
    throw( "no column mapping for $column_name from " . ref($adaptor) )
      unless $column_mappings->{$column_name};

    my $match_values = $require_columns->{$column_name};
    my $value        = &{ $column_mappings->{$column_name} }();
    my $fail         = none { $value eq $_ } @$match_values;
    return undef if $fail;
  }

  #exclude
  for my $column_name ( keys %$exclude_columns ) {
    throw( "no column mapping for $column_name from " . ref($adaptor) )
      unless $column_mappings->{$column_name};
    my $match_values = $exclude_columns->{$column_name};
    my $value        = &{ $column_mappings->{$column_name} }();
    my $fail         = any { $value eq $_ } @$match_values;
    return undef if $fail;
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

=h1 filter_and_update_for_chip_control
  ChIP-seq should have a control, tagged as 'input DNA' (see experiment metadata spec)
  ERSA need each non-input run to have a control run
  We take a list of lookups, and use the first run_id available (order matters).
  The intention is that we have two lookups -
    1 generated automatically (low priotiry)
    1 maintained by hand to handle exceptions, special cases etc (high priority)  
=cut

sub filter_and_update_for_chip_control {
  my ( $self, $run, $experiment, $input_run_id_lookups, $output_hash ) = @_;

  if ( $experiment->library_strategy ne 'ChIP-seq' ) {
    return 1;
  }
  my $experiment_target = first { $_ }
  map { $_->attribute_value }
    grep { uc( $_->attribute_name ) eq 'EXPERIMENT TARGET' }
    @{ $experiment->attributes };

  if ( $experiment_target && uc($experiment_target) eq 'INPUT DNA' ) {
    return 1;
  }

  my $input_run_id =
    first { $_ } map { $_->{ $run->run_source_id } } @$input_run_id_lookups;

  if ( !$input_run_id ) {
    return undef;
  }
  $output_hash->{input_run_id} = $input_run_id;
  return 1;
}

sub filter_by_entity_validated_metadata {
  my ( $self, $entity ) = @_;

  my ($validation_attr) =
    grep { $_->name eq 'Metadata validation status' } $entity->all_attributes;

  if ( !$validation_attr ) {
    return undef;
  }
  if ( $validation_attr->value eq 'error' ) {
    return undef;
  }
  return 1;
}

sub filter_and_update_output_by_biosample {
  my ( $self, %p ) = @_;

  #return 1 if object matches filter conditions, undef otherwise
  #only works for object with an adaptor based on LazyAdaptor
  my $biosample            = $p{biosample};
  my $biosample_attributes = $biosample->organised_attr;
  my $output_hash          = $p{output_hash};
  my $output_attributes    = $p{output_attributes};
  my $require_attributes   = $p{require_attributes};
  my $exclude_attributes   = $p{exclude_attributes};

  if ( $biosample_attributes->{'Metadata validation status'} ) {
    my ($validation_attr) =
      @{ $biosample_attributes->{'Metadata validation status'} };
    return undef if ( $validation_attr->value eq 'error' );
  }

  #require
  for my $attribute_name ( keys %$require_attributes ) {
    my $ok               = 0;
    my $match_conditions = $require_attributes->{$attribute_name};
    my $attributes       = $biosample_attributes->{$attribute_name};

  ATTR: for my $attribute (@$attributes) {
      for my $match_condition (@$match_conditions) {

        #term source id matching
        if ( defined $match_condition->{term_source_id}
          && defined $attribute->id
          && $match_condition->{term_source_id} eq $attribute->id )
        {
          $ok = 1;
          last ATTR;
        }

        #value matching
        if ( defined $match_condition->{value}
          && defined $attribute->value
          && $match_condition->{value} eq $attribute->value )
        {
          $ok = 1;
          last ATTR;
        }
      }
    }

    #no attribute matches
    if ( !$ok ) {
      return undef;
    }
  }

  #exclude
  for my $attribute_name ( keys %$exclude_attributes ) {
    my $ok               = 1;
    my $match_conditions = $exclude_attributes->{$attribute_name};
    my $attributes       = $biosample_attributes->{$attribute_name};

  ATTR: for my $attribute (@$attributes) {
      for my $match_condition (@$match_conditions) {

        #term source id matching
        if ( defined $match_condition->{term_source_id}
          && defined $attribute->id
          && $match_condition->{term_source_id} eq $attribute->id )
        {
          $ok = 0;
          last ATTR;
        }

        #value matching
        if ( defined $match_condition->{value}
          && defined $attribute->value
          && $match_condition->{value} eq $attribute->value )
        {
          $ok = 0;
          last ATTR;
        }
      }
    }

    #no attribute matches
    if ( !$ok ) {
      return undef;
    }
  }

  #output attributes
  for my $attribute_name (@$output_attributes) {
    my $attributes = $biosample_attributes->{ lc($attribute_name) };
    if ( $attributes && @$attributes ) {
      $output_hash->{biosample_attributes}{$attribute_name} =
        [ map { $_->to_hash } @$attributes ];
    }
  }

  return 1;
}

1;
