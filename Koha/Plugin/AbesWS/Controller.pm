package Koha::Plugin::AbesWS::Controller;

use Modern::Perl;
use utf8;
use Koha::Cache;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Koha::Plugin::AbesWS;
use Search::Elasticsearch;
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
    my $cache_key = "abes-biblio-$author_ppn";
    my $publications = $cache->get_from_cache($cache_key);
    my $render = sub {
        $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => [],
            },
            json => $publications,
        );
    };
    if ($publications) {
        $logger->warn("récup dans le cache\n");
        return $render->();
    }
    $publications = { name => '', ppn => $author_ppn, roles => [] };

    my $ua = Mojo::UserAgent->new;
    $ua = $ua->connect_timeout(15);
    my $url_base = 'https://www.idref.fr';
    my $url = "$url_base/$author_ppn.xml";
    my $response = $ua->get($url)->result;
    if (!$response->is_success) {
        $logger->warn(Dump($response->message));
        return $render->();
    }
    my $xml = $response->body;
    my $record = MARC::Moose::Record::new_from($xml, 'Marcxml');
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

    $url = "$url_base/services/biblio/$author_ppn.json";
    #$logger->warn("get $url");
    $response = $ua->get($url)->result;
    if (!$response->is_success) {
        $logger->warn(Dump($response->message));
        return $render->();
    }

    my $json = $response->json;
    my $result = $json->{sudoc}->{result};
    return $render->() if $result->{countRoles} == 0;

    $publications->{name} = join(' / ', @names);
    $publications->{notes} = \@notes if @notes;
    $publications->{altnames} = \@altnames if @altnames;
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
        push @{$publications->{roles}}, $role;
    }

    my $ec = C4::Context->config('elasticsearch');
    my $e = Search::Elasticsearch->new( nodes => $ec->{server} );
    my $query = {
        index => $ec->{index_name} . '_biblios',
        body => {
            _source => ["ppn"],
            size => '10000',
            query => { terms => { ppn => $ppn } }
        }
    };
    #$logger->warn(join(' ', @$ppn));
    my $res = $e->search($query);
    #$logger->warn('retour query ES');
    my $hits = $res->{hits}->{hits};
    my $ppn_to_bib;
    for my $hit (@$hits) {
        my $ppn = $hit->{_source}->{ppn}->[0];
        $ppn_to_bib->{$ppn} = $hit->{_id};
    }
    for my $role (@{$publications->{roles}}) {
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
    #$logger->warn('Mise en cache : ' . $pc->{opac}->{publication}->{expiry});
    $cache->set_in_cache($cache_key, $publications, { expiry => $pc->{opac}->{publication}->{expiry} });

    $render->();
}

1;
