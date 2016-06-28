
=head1 NAME

 ReseqTrack::Hive::PipeConfig::ErsaDataDelivery_conf

=head1 SYNOPSIS

  Pipeline must be seeded by the collection table of a ReseqTrack database
  e.g. use the seeding module ReseqTrack::Hive::PipeSeed::BasePipeSeed with table set to collection

  Here is an example pipeline configuration to load using reseqtrack/scripts/pipeline/load_pipeline_from_conf.pl

[ERSA data delivery]
table_name=collction
config_module=ReseqTrack::Hive::PipeConfig::ErsaDataDelivery_conf
  

  Options that have defaults but you will often want to set them in your pipeline.cofig_options table/column:

      -seeding_module, (default is ReseqTrack::Hive::PipeSeed::BasePipeSeed) override this with a project-specific module
      -seeding_options, hashref passed to the seeding module.  Override the defaults only if using a different seeding module.

      -sample_columns, default is ['sample_source_id', 'sample_alias'].
      -run_columns, default is ['run_source_id', 'run_source_id'],
      -study_columns, default is ['study_source_id']
      -experiment_columns, -sample attributes, -run_attributes, -experiment_attributes, study_attributes, default is [] for each one.
            These parameters define what meta information parameters are added to the flow of information around the hive pipeline
            Add to these arrays if your pipeline uses any extra meta information, e.g. when naming the final output files.
            e.g. for 1000genomes project you might want -sample_attributes POPULATION

      -require_run_columns, default is { status => ['public'], }
      -exlude_run_columns, -require_run_attributes, -exclude_run_attributes, default is {} for each one of these
            Use these hashrefs to control what runs are used to seed the pipeline
            e.g. -require_run_columns instrument_platform=ILLUMINA
            e.g. -exclude_run_attributes BASE_COUNT=0

      -root_output_dir, (default is your current directory) This is where manifest files go

  Options that are required, but will be passed in by reseqtrack/scripts/init_pipeline.pl:

      -pipeline_db -host=???
      -pipeline_db -port=???
      -pipeline_db -user=???
      -dipeline_db -dbname=???
      -reseqtrack_db -host=???
      -reseqtrack_db -user=???
      -reseqtrack_db -port=???
      -reseqtrack_db -pass=???

=cut

package ReseqTrack::Hive::PipeConfig::ErsaDataDelivery_conf;

use strict;
use warnings;

use base ('ReseqTrack::Hive::PipeConfig::ReseqTrackGeneric_conf');

sub default_options {
  my ($self) = @_;

  return {
    %{ $self->SUPER::default_options() }
    ,    # inherit other stuff from the base class

    pipeline_name =>
      'ersa_dump',  # name used by the beekeeper to prefix job names on the farm
    biosample_data_file => '/homes/davidr/perl_code/faang_test/samples.json',
    experiment_data_file =>
      '/homes/davidr/perl_code/faang_test/faang_experiments.json',
    manifest_output_dir => '/hps/cstor01/nobackup/faang/davidr/ersa_delivery',
    run_input_lookup_files => [
      '/homes/davidr/perl_code/faang_test/input_lookup_manual.json',
      '/homes/davidr/perl_code/faang_test/input_lookup_auto.json'
    ],

    #output
    collection_columns    => [ 'name', 'type' ],
    collection_attributes => [],
    file_columns          => [ 'name', 'md5' ],
    file_attributes       => [],

    sample_attribute_keys => [],
    sample_columns        => ['biosample_id'],

    run_attribute_keys => [],
    run_columns =>
      [ 'run_id', 'run_source_id', 'center_name', 'run_center_name' ],

    study_attribute_keys => [],
    study_columns        => ['study_source_id'],

    experiment_attribute_keys => [ 'experiment target', 'assay type' ],
    experiment_columns        => [
      'experiment_id',    'experiment_source_id',
      'library_strategy', 'library_layout'
    ],

    biosample_attributes => [
      'Sample Name', 'Organism', 'Sex', 'material', 'breed', 'organism part',
      'cell type',
      'health status at collection',
      'developmental stage'
    ],

    #filtering
    fastq_collection_type       => 'FASTQ',
    fastq_collection_table_name => 'file',

    require_collection_columns => {
      type       => $self->o('fastq_collection_type'),
      table_name => $self->o('fastq_collection_table_name')
    },
    exclude_collection_columns    => {},
    exclude_collection_attributes => {},
    require_collection_attributes => {},

    require_run_columns    => { status => ['public'], },
    require_run_attributes => {},
    exclude_run_attributes => {},
    exclude_run_columns    => {},

    require_experiment_columns => {
      status              => ['public'],
      library_strategy    => ['ChIP-Seq'],
      instrument_platform => ['ILLUMINA'],
    },
    require_experiment_attributes => {},
    exclude_experiment_attributes => {},
    exclude_experiment_columns    => {},

    require_study_columns    => { status => ['public'], },
    require_study_attributes => {},
    exclude_study_attributes => {},
    exclude_study_columns    => {},

    require_sample_columns    => { status => ['public'], },
    require_sample_attributes => {},
    exclude_sample_attributes => {},
    exclude_sample_columns    => {},

    require_biosample_attributes => {

#TODO uncomment the following block in production, else you'll try to give ERSA goat data
#      Organism =>
#        [ #TODO consider expanding this to include sub-species, e.g. sus scrofa domesticus
#        { term_source_id => 9913 },    #bos taurus
#        { term_source_id => 9031 },    #gallus gallus
#        { term_source_id => 9796 },    #equus caballus
#        { term_source_id => 9823 },    #sus scrofa
#        { term_source_id => 9940 },    #ovis aries
#        ]

    },
    exclude_biosample_attributes => {},

    seeding_module  => 'ReseqTrack::Hive::PipeSeed::FaangErsaDump',
    seeding_options => {

      biosample_data_file    => $self->o('biosample_data_file'),
      run_input_lookup_files => $self->o('run_input_lookup_files'),
      experiment_data_file   => $self->o('experiment_data_file'),

      #output of collection
      output_columns    => $self->o('collection_columns'),
      output_attributes => $self->o('collection_attributes'),

      #filtering collection
      require_columns    => $self->o('require_collection_columns'),
      exclude_columns    => $self->o('exclude_collection_columns'),
      require_attributes => $self->o('require_collection_attributes'),
      exclude_attributes => $self->o('exclude_collection_attributes'),

      #filtering by ena metadata
      require_run_columns    => $self->o('require_run_columns'),
      require_run_attributes => $self->o('require_run_attributes'),
      exclude_run_attributes => $self->o('exclude_run_attributes'),
      exclude_run_columns    => $self->o('exclude_run_columns'),

      require_experiment_columns => $self->o('require_experiment_columns'),
      require_experiment_attributes =>
        $self->o('require_experiment_attributes'),
      exclude_experiment_attributes =>
        $self->o('exclude_experiment_attributes'),
      exclude_experiment_columns => $self->o('exclude_experiment_columns'),

      require_sample_columns    => $self->o('require_sample_columns'),
      require_sample_attributes => $self->o('require_sample_attributes'),
      exclude_sample_attributes => $self->o('exclude_sample_attributes'),
      exclude_sample_columns    => $self->o('exclude_sample_columns'),

      require_study_columns    => $self->o('require_study_columns'),
      require_study_attributes => $self->o('require_study_attributes'),
      exclude_study_attributes => $self->o('exclude_study_attributes'),
      exclude_study_columns    => $self->o('exclude_study_columns'),

      #filtering by biosample metadata
      output_biosample_attributes  => $self->o('biosample_attributes'),
      require_biosample_attributes => $self->o('require_biosample_attributes'),
      exclude_biosample_attributes => $self->o('exclude_biosample_attributes'),

      #output of things linked to collection
      output_file_columns    => $self->o('file_columns'),
      output_file_attributes => $self->o('file_attributes'),

      output_run_columns           => $self->o('run_columns'),
      output_run_attributes        => $self->o('run_attribute_keys'),
      output_experiment_columns    => $self->o('experiment_columns'),
      output_experiment_attributes => $self->o('experiment_attribute_keys'),
      output_sample_columns        => $self->o('sample_columns'),
      output_sample_attributes     => $self->o('sample_attribute_keys'),
      output_study_columns         => $self->o('study_columns'),
      output_study_attributes      => $self->o('study_attribute_keys'),
    },

  };
}

sub pipeline_wide_parameters {
  my ($self) = @_;
  return { %{ $self->SUPER::pipeline_wide_parameters }, };
}

sub pipeline_analyses {
  my ($self) = @_;

  my @analyses;

  push(
    @analyses,
    {
      -logic_name  => 'get_seeds',
      -module      => 'ReseqTrack::Hive::Process::SeedFactory',
      -meadow_type => 'LOCAL',
      -parameters  => {
        seeding_module  => $self->o('seeding_module'),
        seeding_options => $self->o('seeding_options'),
      },
      -analysis_capacity => 1,    # use per-analysis limiter
      -flow_into         => {
        '2->A' => ['accu_target'],
        'A->1' => ['write_registration_manifest']
      },
    }
  );

  push(
    @analyses,
    {
      -logic_name  => 'accu_target',
      -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
      -meadow_type => 'LOCAL',
      -flow_into   => { 1 => ['?accu_name=ersa_dump&accu_address={ps_id}'] }
    }
  );

  push(
    @analyses,
    {
      -logic_name => 'load_registration_file',
      -module     => 'ReseqTrack::Hive::Process::LoadFile',
      -parameters => {
        type               => 'ERSA_REGISTRATION',
        file               => '#registration_file#',
        do_pipeline_output => 0,
      },
      -meadow_type => 'LOCAL',
    }
  );

  push(
    @analyses,
    {
      -logic_name  => 'mark_seed_complete',
      -module      => 'ReseqTrack::Hive::Process::UpdateSeed',
      -parameters  => { is_complete => 1, },
      -meadow_type => 'LOCAL',

    }
  );

  push(
    @analyses,
    {
      -logic_name  => 'write_registration_manifest',
      -module      => 'ReseqTrack::Hive::Process::ErsaDumpWriter',
      -meadow_type => 'LOCAL',
      -parameters  => {
        manifest_output_dir =>
          '/hps/cstor01/nobackup/faang/davidr/ersa_delivery',
        source_param_name               => 'ersa_dump',
        output_filename_core_param_name => 'seed_time',
        output_filename_prefix          => 'ersa_dump_',
        output_filename_suffix          => '.csv',
        output_column_delimiter         => ',',
        ontology_attributes             => {
          SAMPLE => [ 'Sex',           'breed', 'material' ],
          TISSUE => [ 'organism part', 'cell type' ],
          CONDITION => [ 'health status at collection', 'developmental stage' ],
        },
        output_project_prefix            => 'FAANG-',
        output_project_suffix_param_name => 'study_source_id'
      },
      -flow_into => {
        1 => ['load_registration_file'],
        2 => ['mark_seed_complete'],

      }
    }
  );

  return \@analyses;
}

1;
