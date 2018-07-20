#!/usr/bin/env perl

use strict;
use warnings;

use WWW::Mechanize;
use JSON -support_by_pp;
use Getopt::Long;
use JSON;
use Data::Dumper;

my ($dev, $authuser, $authpass, $listtoupdate);

GetOptions("dev" => \$dev,
           "authuser=s" => \$authuser,
           "authpass=s" => \$authpass,
           "listtoupdate=s" => \$listtoupdate, #Tab seperated list of BioSample -> field to remove\n
);

die "missing authuser" if !$authuser;
die "missing authpass" if !$authpass;
die "missing list of sample fields to remove" if !$listtoupdate;


my $authurl;

#Obtain AAI access token (if --dev then use dev authentication environment)
if ($dev){
  $authurl = 'https://explore.api.aap.tsi.ebi.ac.uk/auth'
}else{
  $authurl = 'https://api.aai.ebi.ac.uk/auth'
}
my $auth = WWW::Mechanize->new();
$auth->credentials( $authuser => $authpass);
$auth->get($authurl);
my $token = $auth->content();
$token = "Bearer ".$token;

my %biosamplestofix;
#List samples to remove here
open my $fhi, '<', $listtoupdate or die "could not open $listtoupdate $!";
my @lines = <$fhi>;
foreach my $line (@lines){
  chomp($line);
  my @parts = split("\t", $line);
  if ($biosamplestofix{$parts[0]}){
    push($biosamplestofix{$parts[0]}, $parts[1]);
  }else{
    $biosamplestofix{$parts[0]} = [$parts[1]];
  }
}

print Dumper(%biosamplestofix);

my %ontologyMapping = (
  "male" => "http://purl.obolibrary.org/obo/PATO_0000384",
  "female" => "http://purl.obolibrary.org/obo/PATO_0000383"
);


foreach my $key (keys(%biosamplestofix)){
  my $sampleurl = "https://www.ebi.ac.uk/biosamples/samples/".$key;
  my $cellline = fetch_json_by_url($sampleurl);
  foreach my $fieldtofix (@{$biosamplestofix{$key}}){
    my %curatedata;
    my $toprocess = $$cellline{characteristics}{$fieldtofix};
    if($toprocess){
      foreach my $within (@{$toprocess}){
        foreach my $key (keys($within)){
          if ($key eq 'text'){
            $curatedata{text} = $$within{$key};
          }elsif ($key eq 'ontologyTerms'){
            $curatedata{iri} = $$within{$key};
          }elsif ($key eq 'unit'){
            $curatedata{unit} = $$within{$key};
          }
        }
      }
      my $JSONpayload;
      $JSONpayload = '{
      "sample": "'.$key.'",
      "curation": {
        "attributesPre": [
          {
            "type":"'.$fieldtofix.'",
            "value":"'.$curatedata{text}.'",
            "iri":["'.join('","', @{$curatedata{iri}}).'"]
          }
        ],
        "attributesPost": [
          {
            "type":"'.$fieldtofix.'",
            "value":"'.$curatedata{text}.'",
            "iri":["'.$ontologyMapping{$curatedata{text}}.'"]
          }
        ],
        "externalReferencesPre": [],
        "externalReferencesPost": []
      },
      "domain": "self.FAANG_DCC_curation"
      }';
    print $JSONpayload, "\n";
    my $currationbaseurl;
    if ($dev){
      $currationbaseurl = "https://wwwdev.ebi.ac.uk/biosamples/samples/"
    }else{
      $currationbaseurl = "https://www.ebi.ac.uk/biosamples/samples/"
    }
    my $currationurl = $currationbaseurl.$key."/curationlinks";
    print $currationurl, "\n\n";
    my $currate = WWW::Mechanize->new();    
    my $response = $currate->post($currationurl, 
    "Content" => $JSONpayload, 
    "accept" => "application/hal+json",
    "Content-Type" => "application/json",
    "Authorization" => $token
    );
    print $key, "\t", $fieldtofix, "\t", $currate->status, "\n";
    }
  }
}

#use BioSample API to retrieve BioSample records
sub fetch_biosamples_json{
  my ($json_url) = @_;

  my $json_text = &fetch_json_by_url($json_url);
  my @biosamples;
  # Store the first page 
  foreach my $item (@{$json_text->{_embedded}{samples}}){ 
    push(@biosamples, $item);
  }
  # Store each additional page
  while ($$json_text{_links}{next}{href}){  # Iterate until no more pages using HAL links
    $json_text = fetch_json_by_url($$json_text{_links}{next}{href});# Get next page
    foreach my $item (@{$json_text->{_embedded}{samples}}){
      push(@biosamples, $item);  
    }
  }
  return @biosamples;
}

sub fetch_json_by_url{
  my ($json_url) = @_;

  my $browser = WWW::Mechanize->new();
  #$browser->show_progress(1);  # Enable for WWW::Mechanize GET logging
  $browser->get( $json_url );
  my $content = $browser->content();
  my $json = new JSON;
  my $json_text = $json->decode($content);
  return $json_text;
}