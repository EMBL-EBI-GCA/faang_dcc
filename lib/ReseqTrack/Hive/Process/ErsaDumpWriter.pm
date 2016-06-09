package ReseqTrack::Hive::Process::ErsaDumpWriter;

use strict;
use ReseqTrack::Tools::Exception qw(throw);
use autodie;
use base ('ReseqTrack::Hive::Process::BaseProcess');
use File::Path qw(make_path);

use Data::Dumper;

sub run {
  my $self = shift;

  my $source_param_name = $self->param('source_param_name') // 'ersa_dump';
  my $source_data = $self->param_required($source_param_name);

  my $ontology_attributes = $self->param('ontology_attributes') // {
    SAMPLE => [ 'Sex',           'breed', 'material' ],
    TISSUE => [ 'organism part', 'cell type' ],
    CONDITION => [ 'health status at collection', 'developmental stage' ],
  };

  my $output_project_prefix = $self->param('output_project_prefix') // 'FAANG-';
  my $output_project_suffix_param_name =
    $self->param('output_project_suffix_param_name') // 'study_source_id';

  my $output_filename_core_param_name =
    $self->param('output_filename_core_param_name') // 'seed_time';
  my $output_filename_core =
    $self->param_required($output_filename_core_param_name);
  my $output_dir             = $self->param_required('manifest_output_dir');
  my $output_filename_prefix = $self->param('output_filename_prefix')
    // 'ersa_dump_';
  my $output_filename_suffix = $self->param('output_filename_suffix') // '.csv';

  my $output_column_delimiter = $self->param('output_column_delimiter') // ',';

  make_path($output_dir);

  my $file_name =
      $output_dir . '/'
    . $output_filename_prefix
    . $output_filename_core
    . $output_filename_suffix;

  open( my $fh, '>', $file_name );

  my @columns = qw(
    accession epigenome assay br tr is_control md5sum local_url analysis Project/lab ontologies control_id species
  );

  print $fh join( $output_column_delimiter, @columns ) . $/;

  for my $x (@$source_data) {
    my %output =
      $self->construct_output( $x, $ontology_attributes,
      $output_project_prefix, $output_project_suffix_param_name );
    print $fh
      join( $output_column_delimiter, map { $_ // '' } @output{@columns} ) . $/;
  }

  print $fh Dumper($source_data);

  close($fh);

}

sub construct_output {
  my ( $self, $x, $ontology_attributes, $output_project_prefix,
    $output_project_suffix_param_name )
    = @_;

  my %output;
  my %biosample_attributes = %{ $x->{biosample_attributes} };

  #TODO
  #control_id

  #identity
  $output{accession} = $x->{run_source_id};
  $output{epigenome} = $biosample_attributes{'Sample Name'}[0]{value};

  $output{species} = $biosample_attributes{'Organism'}[0]{value};
  $output{'Project/lab'} =
    $output_project_prefix . $x->{$output_project_suffix_param_name};
  $output{tr} = $x->{experiment_source_id};

  #assay
  $output{analysis}   = $x->{library_strategy};
  $output{assay}      = $x->{experiment_type};
  $output{is_control} = 0;

  if ( $output{assay} eq 'input DNA' ) {
    $output{assay}      = 'WCE';
    $output{is_control} = 1;
  }

  #files
  my $f = $x->{collection_files}[0];
  $output{md5sum}    = $f->{md5};
  $output{local_url} = $f->{name};

  #sample description ontology entries
  my @ontologies;

  for my $ont_key (%$ontology_attributes) {
    for my $attribute_key ( @{ $ontology_attributes->{$ont_key} } ) {
      my $attributes = $biosample_attributes{$attribute_key};

      next if ( !$attributes );

  #Format:
  #SAMPLE-EFO:0001086;TISSUE-EFO:0001087;TISSUE-CL:0000863;CONDITION-EFO:0001090
      push @ontologies, map { $ont_key . '-' . $_->{term_source_id} }
        map { $_->{term_source_id} =~ s/_/:/ }
        grep { defined $_->{term_source_id} } @$attributes;
    }
  }

  $output{ontologies} = join( ';', @ontologies );

  return %output;
}

1;
