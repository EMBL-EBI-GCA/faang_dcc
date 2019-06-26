"""
This script is to check all values holding in the ElasticSearch for URI-type fields are valid URLs
"""
import re
import click
from elasticsearch import Elasticsearch
# defines the fields to check for valid URLs. These field lists are generated from the fields with
# uri_value type in the ruleset
URLS = dict()
URLS['organism'] = ['pedigree']
URLS['specimen'] = ['availability',
                    'specimenFromOrganism.specimenCollectionProtocol.url', 'specimenFromOrganism.specimenPictureUrl',
                    'poolOfSpecimens.poolCreationProtocol.url', 'poolOfSpecimens.specimenPictureUrl',
                    'cellSpecimen.purificationProtocol.url',
                    'cellCulture.cellCultureProtocol.url',
                    'cellLine.cultureProtocol.url'
                    ]
URLS['experiment'] = ['experimentalProtocol.url', 'extractionProtocol.url',
                      'ATAC-seq.transposaseProtocol.url',
                      'BS-seq.bisulfiteConversionProtocol.url', 'BS-seq.pcrProductIsolationProtocol.url',
                      'ChiP-seq histone.chipProtocol.url', 'ChiP-seq histone.chipProtocol.url',
                      'DNase-seq.dnaseProtocol.url',
                      'Hi-C.hi-cProtocol.url',
                      'RNA-seq.rnaPreparation3AdapterLigationProtocol.url',
                      'RNA-seq.rnaPreparation5AdapterLigationProtocol.url',
                      'RNA-seq.libraryGenerationPcrProductIsolationProtocol.url',
                      'RNA-seq.preparationReverseTranscriptionProtocol.url', 'RNA-seq.libraryGenerationProtocol.url',
                      'WGS.libraryGenerationPcrProductIsolationProtocol.url', 'WGS.libraryGenerationProtocol.url'
                      ]
# defines what are the id columns in the specific type of data
IDS = dict()
IDS['organism'] = 'biosampleId'
IDS['specimen'] = 'biosampleId'
IDS['experiment'] = 'accession'

# use click library to get command line parameters
@click.command()
@click.option(
    '--es_host',
    default="http://wp-np3-e2:9200",
    help='Specify the Elastic Search server (port should be included), default to be http://wp-np3-e2:9200.'
)
@click.option(
    '--es_index_prefix',
    default='faang_build_3',
    help='Specify which build to check'
)
def main(es_host, es_index_prefix) -> None:
    es = Elasticsearch(es_host)
    body = {
        "query": {
            "term": {"standardMet": "FAANG"}
        }
    }
    for es_type in URLS.keys():
        # get the size of all matching records
        res = es.search(index=f"{es_index_prefix}_{es_type}", body=body)
        id_field = IDS[es_type]
        size = res['hits']['total']
        print(f"{size} {es_type}s meeting FAANG standard")
        # dynamically assign the size
        params = {
            "size": size
        }
        res = es.search(index=f"{es_index_prefix}_{es_type}", body=body, params=params)
        for hit in res['hits']['hits']:
            hit = hit['_source']
            fields = URLS[es_type]
            for field in fields:
                not_found = False
                elmts = field.split(".")
                curr = hit
                for elmt in elmts:
                    if elmt in curr:
                        curr = curr[elmt]
                    else:
                        not_found = True
                        break
                if not not_found and curr:
                    valid = is_url(curr)
                    if not valid:
                        print(f"the value of field {field} in {hit[id_field]} is not a valid URL: {curr}")


def is_url(url: str) -> bool:
    """
    check whether a string is a valid URI
    :param url: the string to be checked
    :return: True if a valid URI, False otherwise
    """
    if type(url) is not str:
        print(url)
        raise TypeError("The method only take str as its input")
    # https://stackoverflow.com/questions/161738/what-is-the-best-regular-expression-to-check-if-a-string-is-a-valid-url
    pattern = re.compile(r"^((http|ftp)s?:\/\/)?(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b"
                         r"([-a-zA-Z0-9@:%_\+.~#?&\/=]*)$")
    m = re.search(pattern, url)
    if m:
        return True
    return False


if __name__ == "__main__":
    main()
