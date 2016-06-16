#!/usr/bin/env perl
use strict;
use warnings;

use Carp;
use Getopt::Long;
use Data::Dumper;

use JSON::MaybeXS;
use autodie;

use ReseqTrack::DBSQL::DBAdaptor;

my %rst_db;
my $library_strategy          = 'ChIP-Seq';
my $comparison_attribute_name = 'experiment target';
my $input_attribute_value     = 'input DNA';
my $run_scoring_attribute     = 'READ_COUNT';
my $run_scoring_use_lowest    = undef;
my $output_file;

my $help;

GetOptions(

  #source
  "dbhost=s" => \$rst_db{-host},
  "dbuser=s" => \$rst_db{-user},
  "dbpass=s" => \$rst_db{-pass},
  "dbport=s" => \$rst_db{-port},
  "dbname=s" => \$rst_db{-dbname},

  #searching
  "library_strategy=s"          => \$library_strategy,
  "comparison_attribute_name=s" => \$comparison_attribute_name,
  "input_attribute_value=s"     => \$input_attribute_value,

  #how to choose which input run to prefer
  "run_scoring_attribute=s" => \$run_scoring_attribute,
  "run_scoring_use_lowest"  => \$run_scoring_use_lowest,

  #output
  "output_file=s" => \$output_file,
  #misc
  "help" => \$help,
) or croak "Unexpected arguments: $!";

my $rst = ReseqTrack::DBSQL::DBAdaptor->new(%rst_db);
croak "could not connect to reseqtrack db" unless ($rst);
my $ea = $rst->get_ExperimentAdaptor();

my $experiments =
  $ea->fetch_by_column_name( 'library_strategy', $library_strategy );

my ( $input_experiments, $other_experiments ) =
  filter_experiments( $experiments, $comparison_attribute_name,
  $input_attribute_value );

my $preferred_input_per_sample =
  preferred_input_run_per_sample( $input_experiments, $run_scoring_attribute,
  $run_scoring_use_lowest );

my $preferred_input_per_run =
  preferred_input_per_run( $other_experiments, $preferred_input_per_sample );

write_out($preferred_input_per_run,$output_file);

sub write_out {
  my ($preferred_input_per_run,$output_file) =@_;
  
  open (my $fh, '>', $output_file);
  
  my $json = JSON->new->pretty(1);
  
  print $fh $json->encode($preferred_input_per_run);
  
  close $fh;
}

sub preferred_input_per_run {
  my ( $experiments_by_sample, $preferred_input_per_sample ) = @_;

  my %preferred_input_per_run;

SAMPLE: for my $sample_id ( keys %$experiments_by_sample ) {

    my $input_run_id = $preferred_input_per_sample->{$sample_id} // '';

    my $experiments = $experiments_by_sample->{$sample_id};

  EXPERIMENT: for my $experiment (@$experiments) {
      my $runs = $experiment->runs;
    RUN: for my $run (@$runs) {
        $preferred_input_per_run{ $run->run_source_id } = $input_run_id;
      }
    }
  }

  return \%preferred_input_per_run;
}

=h1 preferred_input_per_sample
  take a hash keyed on the biosample id, and each value is a list
  of experiment objects
  gives a hash keyed on biosample id where each value is the 'best'run 
=cut

sub preferred_input_run_per_sample {
  my ( $input_experiments_by_sample, $run_scoring_attribute,
    $run_scoring_use_lowest )
    = @_;

  my %preferred_run;

SAMPLE: for my $sample_id ( keys %$input_experiments_by_sample ) {
    my $experiments = $input_experiments_by_sample->{$sample_id};

    my $best_run;
    my $best_run_score;

  EXPERIMENT: for my $experiment (@$experiments) {
      my $runs = $experiment->runs;

    RUN: for my $run (@$runs) {
        my $attributes = $run->attributes_hash;
        my $score;

        if ( $attributes->{$run_scoring_attribute} ) {
          $score = $attributes->{$run_scoring_attribute}->attribute_value;
        }

        if ( !defined $best_run ) {
          $best_run       = $run;
          $best_run_score = $score;
          next RUN;
        }

        if ( !defined $score ) {
          next RUN;
        }

        if ( !defined $best_run_score ) {
          $best_run       = $run;
          $best_run_score = $score;
          next RUN;
        }

        if ( $run_scoring_use_lowest && $score < $best_run_score ) {
          $best_run       = $run;
          $best_run_score = $score;
          next RUN;
        }

        if ( $score > $best_run_score ) {
          $best_run       = $run;
          $best_run_score = $score;
          next RUN;
        }
      }    #END OF RUN
    }    #END OF EXPERIMENT

    $preferred_run{$sample_id} = $best_run->run_source_id;
  }    #END OF SAMPLE

  return \%preferred_run;
}

=h1 filter_experiments
  take a list of experiments and organise them into two hashes,
  one for input sequencing, one for everything else.
  Each hash is keyed on the biosample id, and each value is a list
  of experiment objects
=cut

sub filter_experiments {
  my ( $experiments, $comparison_attribute_name, $input_attribute_value ) = @_;

  my $input_experiments = {};
  my $other_experiments = {};

  for my $experiment (@$experiments) {
    my $attributes  = $experiment->attributes_hash;
    my $target_hash = $other_experiments;

    my $biosample_id = $experiment->sample()->biosample_id();

    if ( $attributes->{$comparison_attribute_name}
      && $attributes->{$comparison_attribute_name}->attribute_value eq
      $input_attribute_value )
    {
      $target_hash = $input_experiments;
    }

    $target_hash->{$biosample_id} = [] if ( !$target_hash->{$biosample_id} );

    my $target_list = $target_hash->{$biosample_id};

    push @$target_list, $experiment;
  }

  return ( $input_experiments, $other_experiments );
}

