package Koha::Plugin::AbesWS::Controller;

use Modern::Perl;
use utf8;
use Koha::Cache;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Koha::Plugin::AbesWS;
use Search::Elasticsearch;
use Koha::SearchEngine::Elasticsearch;
use MARC::Moose::Record;
use YAML;

use Mojo::Base 'Mojolicious::Controller';

sub get {
    my $c = shift->openapi->valid_input or return;

    my $logger = Koha::Logger->get({ interface => 'api' });
    my $plugin = Koha::Plugin::AbesWS->new;
    my $pc  = $plugin->config();

    my $author_ppn = $c->validation->param('ppn');
    my $cache = $plugin->{cache};
    my $cache_key = "abesws-ppn-$author_ppn";
    my $infos = $cache->get_from_cache($cache_key);
    my $render = sub {
        $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => [],
            },
            json => $infos,
        );
    };
    if ($infos) {
        $logger->debug("Infos récupérées dans le cache");
        return $render->();
    }
    $infos = {
        ppn => $author_ppn,
        name => '',
        notes => undef,
        altnames => undef,
        roles => [],
        altid => {},
    };

    my $ua = Mojo::UserAgent->new;
    $ua = $ua->connect_timeout(15);
    my $response;
    my $url_base = 'https://www.idref.fr';
    my $url;

    if ($pc->{idref}->{opac}->{info}->{enabled} ||
        $pc->{idref}->{opac}->{toid}->{enabled})
    {
        $url = "$url_base/$author_ppn.xml";
        $logger->debug("Infos sur auteur: $url");
        my $response = $ua->get($url)->result;
        if (!$response->is_success) {
            $logger->warn(Dump($response->message));
            return $render->();
        }
        my $xml = $response->body;
        my $record = MARC::Moose::Record::new_from($xml, 'Marcxml');

        # 1) Récupération des infos détaillées d'un auteur
        if ($pc->{idref}->{opac}->{info}->{enabled}) {
            my @names = map {
                join(', ', map { $_->[1] } grep { $_->[0] =~ /[a-z]/ } @{$_->subf} )
            } $record->field('2..');
            my @altnames;
            for my $field ($record->field('4..')) {
                push @altnames, join(', ', map { $_->[1] } grep { $_->[0] =~ /[a-z]/ } @{$field->subf});
            }
            my @notes;
            for my $field ($record->field('3..')) {
                push @notes, $field->subfield('a');
            }
            $infos->{name} = join(' / ', @names);
            $infos->{notes} = \@notes if @notes;
            $infos->{altnames} = \@altnames if @altnames;
        }

        # 2) Les identifiants externes
        if ($pc->{idref}->{opac}->{toid}->{enabled}) {
            my $altid = $infos->{altid};
            for my $field ($record->field('010|033|035')) {
                my $source = $field->subfield('2');
                next unless $source;
                my $id = $field->subfield('a');
                $altid->{$source} = $id;
            }
        }
    }

    # 3) Les publications de l'auteur
    if ($pc->{idref}->{opac}->{publication}->{enabled}) {
        $url = "$url_base/services/biblio/$author_ppn.json";
        $logger->debug("Publications de l'auteur: $url");
        $response = $ua->get($url)->result;
        if (!$response->is_success) {
            $logger->warn(Dump($response->message));
            return $render->();
        }

        my $json = $response->json;
        my $result = $json->{sudoc}->{result};
        return $render->() if $result->{countRoles} == 0;

        $result->{role} = [ $result->{role} ] if ref($result->{role}) ne 'ARRAY';
        my $ppn;
        for my $r (@{$result->{role}}) {
            my $role = {
                code => $r->{unimarcCode},
                label => $r->{roleName},
                docs => [],
            };
            $r->{doc} = [ $r->{doc} ] if ref $r->{doc} ne 'ARRAY';
            for my $doc ( @{$r->{doc}} ) {
                push @{$role->{docs}}, {
                    ppn => $doc->{ppn},
                    citation => $doc->{citation},
                };
                push @$ppn, $doc->{ppn};
            }
            push @{$infos->{roles}}, $role;
        }

        my $ppn_to_bib = {};
        if ($pc->{idref}->{opac}->{publication}->{elasticsearch}) {
            my $ec = C4::Context->config('elasticsearch');
            my $e = Search::Elasticsearch->new(
                Koha::SearchEngine::Elasticsearch::get_elasticsearch_params()
            );
            my $query = {
                index => $ec->{index_name} . '_biblios',
                body => {
                    _source => ["ppn"],
                    size => '10000',
                    query => { terms => { ppn => $ppn } }
                }
            };
            my $res = $e->search($query);
            my $hits = $res->{hits}->{hits};
            for my $hit (@$hits) {
                my $ppn = $hit->{_source}->{ppn}->[0];
                $ppn_to_bib->{$ppn} = $hit->{_id};
            }
        }

        for my $role (@{$infos->{roles}}) {
            my @docs = @{$role->{docs}};
            for my $d (@docs) {
                my $bib = $ppn_to_bib->{ $d->{ppn} };
                $d->{bib} = $bib if $bib;
            }
            my $key = sub {
                my $doc = shift;
                ($doc->{bib} ? 'a' : 'b') . $doc->{citation};
            };
            @docs = sort { $key->($a) cmp $key->($b) } @docs;
            $role->{docs} = \@docs;
        }
    }

    my $expiry = $pc->{idref}->{opac}->{expiry};
    $logger->debug("Mise en cache avec timeout: $expiry");
    $cache->set_in_cache($cache_key, $infos, { expiry => $expiry });

    $render->();
}

1;
