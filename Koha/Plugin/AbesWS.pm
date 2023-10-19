package Koha::Plugin::AbesWS;

use Modern::Perl;
use utf8;
use base qw(Koha::Plugins::Base);
use CGI qw(-utf8);
use C4::Context;
use C4::Biblio;
use Koha::Cache;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use JSON qw/ to_json from_json /;
use Template;
use Encode qw/ decode /;
use MARC::Moose::Record;
use Pithub::Markdown;
use YAML;


## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'AbesWS',
    canonicalname   => 'koha-plugin-abesws',
    description     => 'Utilisation de services web Abes',
    author          => 'Tamil s.a.r.l.',
    date_authored   => '2023-10-16',
    date_updated    => "2023-10-18",
    minimum_version => '22.11.00.000',
    maximum_version => undef,
    copyright       => '2023',
    version         => '1.0.2',
};


my $conf = {
    bibliocontrol => {
        errors => [
            'une 225 est presente sans 410 ni 461',
            'une 700 701 702 n a pas de code fonction',
            'une 181 est presente en meme temps qu une 200$b',
        ],
    },
    algo => {
        tdoc => {
            bib => {
                Aa => 'Monographie imprimée',
                Ab => 'Périodique imprimé',
                Ad => 'Collection imprimée',
                Ba => 'Document audiovisuel',
                Ga => 'Enregistrement sonore musical',
                Ka => 'Carte imprimée',
                Ma => 'Partition imprimée',
                Na => 'Enregistrement sonore non musical',
                Oa => 'Document électronique',
                Ob => 'Périodique électronique',
                Od => 'Collection de documents électroniques',
                Or => 'Recueil factice de documents électroniques',
                Va => 'Objet',
                Za => 'Document multimédia multisupport',
                Zd => 'Collection de documents multimédias multisupports',
            },
            aut => {
                Tb => 'Collectivité / Congrès',
                Td => 'Noms communs',
                Tp => 'Nom de personne',
                Tu => 'Titre uniforme',
            },
        },
    },
};

$conf->{algo}->{tdoc}->{get_array} = sub {
    my @tdocs;
    for ( (['bib', 'Biblio'], ['aut', 'Autorité']) ) {
        my ($code, $type) = @$_;
        my $tdoc = $conf->{algo}->{tdoc}->{$code};
        for ( keys %$tdoc ) {
            push @tdocs, [$_, "$type: " . $tdoc->{$_}];
        }
    }
    return \@tdocs;
};

$conf->{algo}->{tdoc}->{get_hash} = sub {
    my %tdoc_hash;
    for ( (['bib', 'Biblio'], ['aut', 'Autorité']) ) {
        my ($code, $type) = @$_;
        my $tdoc = $conf->{algo}->{tdoc}->{$code};
        for ( keys %$tdoc ) {
            $tdoc_hash{$_} = "$type: " . $tdoc->{$_};
        }
    }
    return \%tdoc_hash;
};

sub new {
    my ($class, $args) = @_;

    $args->{metadata} = $metadata;
    $args->{metadata}->{class} = $class;
    $args->{cache} = Koha::Cache->new();
    $args->{logger} = Koha::Logger->get({ interface => 'intranet' });

    $class->SUPER::new($args);
}

sub config {
    my $self = shift;

    my $c = $self->{args}->{c};
    unless ($c) {
        $c = $self->retrieve_data('c');
        if ($c) {
            utf8::encode($c);
            $c = decode_json($c);
        }
        else {
            $c = {};
        }
    }
    $c->{url} ||= {};
    $c->{url}->{api} ||= 'https://www.sudoc.fr/services';
    $c->{url}->{algo} ||= 'https://www.idref.fr/AlgoLiens';
    $c->{url}->{qualimarc} ||= 'https://qualimarc.sudoc.fr/api/v1';
    $c->{url}->{timeout} ||= 600;
    $c->{detail}->{qualimarc}->{analyse} ||= 'COMPLETE';
    $c->{idref} ||= {};
    $c->{idref}->{url} ||= 'https://www.idref.fr';
    $c->{idref}->{idclient} ||= 'tamil';
    my @fields = split /\r|\n/, $c->{idref}->{catalog}->{fields};
    @fields = grep { $_ } @fields;
    $c->{idref}->{catalog}->{fields_array} = \@fields;
    $c->{idef}->{opac}->{publication}->{expiry} ||= 86400;

    $c->{metadata} = $self->{metadata};

    my @rcr = split /\r|\n/, $c->{iln}->{rcr};
    @rcr = grep { $_ } @rcr;
    @rcr = map {
        /^([0-9]+) +(.+)$/ ? [$1, $2] : [$_, $_];
    } @rcr;
    $c->{iln}->{rcr_array} = \@rcr;

    my %bib_per_rcr = map { $_->[0] => $_->[1] } @rcr;
    $c->{iln}->{rcr_hash} = \%bib_per_rcr;

    $self->{args}->{c} = $c;

    return $c;
}

sub get_form_config {
    my $cgi = shift;
    my $c = {
        url => {
            api       => undef,
            algo      => undef,
            qualimarc => undef,
            timeout   => undef,
        },
        iln => {
            iln => undef,
            rcr => undef,
            ppn => undef,
        },
        bibliocontrol => {
            t225 => 0,
            f000 => 0,
            t181 => 0,
            link_koha => 'marc',
        },
        detail => {
            enabled => 0,
            ppn_selector => undef,
            location => 0,
            qualimarc => {
                enabled => 0,
                analyse => undef,
            },
        },
        idref => {
            url => undef,
            idclient => undef,
			catalog => {
				enabled => 0,
				fields => 0,
	        },
            opac => {
                publication => {
                    enabled => 0,
                    expiry => undef,
                },
            },
        },
    };

    my $set;
    $set = sub {
        my ($node, $path) = @_;
        return if ref($node) ne 'HASH';
        for my $subkey ( keys %$node ) {
            my $key = $path ? "$path.$subkey" : $subkey;
            my $subnode = $node->{$subkey};
            if ( ref($subnode) eq 'HASH' ) {
                $set->($subnode, $key);
            }
            else {
                $node->{$subkey} = $cgi->param($key);
            }
        }
    };

    $set->($c);
    return $c;
}

sub configure {
    my ($self, $args) = @_;
    my $cgi = $self->{'cgi'};

    if ( $cgi->param('save') ) {
        my $c = get_form_config($cgi);
        my $rcr = [
            map { s/'/''/g }
            split /\n/, $c->{iln}->{rcr}
        ];
        #FIXME: qu'est-ce ?
        map { s/'/''/g }
        split /\n/, $c->{idref}->{catalog}->{fields};
        $self->store_data({ c => encode_json($c) });
        print $self->{'cgi'}->redirect(
            "/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::AbesWS&method=tool");
    }
    else {
        my $template = $self->get_template({ file => 'configure.tt' });
        $template->param( c => $self->config() );
        $self->output_html( $template->output() );
    }
}

sub tool {
    my ($self, $args) = @_;

    my $cgi = $self->{cgi};

    my $template;
    my $c = $self->config();
    my $ws = $cgi->param('ws');
    my $logger = $self->{logger};
    if ( $ws ) {
        if ($ws eq 'realign') {
            $template = $self->get_template({ file => 'realign.tt' });
            my $table = $self->get_qualified_table_name('action');
            my $actions = C4::Context->dbh->selectall_arrayref(qq{
                SELECT id, start, end FROM $table
                WHERE type = 'realign'
                ORDER BY start DESC
            }, { Slice => {} });
            $template->param( actions => $actions );
        }
        elsif ($ws eq 'realignid') {
            $template = $self->get_template({ file => 'realignid.tt' });
            $template->param( c => $c );
            my $table = $self->get_qualified_table_name('action');
            my $id = $cgi->param('id');
            my $action = C4::Context->dbh->selectall_arrayref(qq{
                SELECT * FROM $table
                WHERE type = 'realign'
                AND id=$id
            }, { Slice => {} });
            my $realign = {};
            if ($action) {
                $action = $action->[0];
                $realign = $action->{result};
                #$logger->warn($realign);
                $realign = from_json($realign);
            }
            my @realign;
            for my $biblionumber (keys %$realign ) {
                for my $action ( @{$realign->{$biblionumber}} ) {
                    $action->{bn} = $biblionumber;
                    push @realign, $action;
                }
            }
            $template->param( realign => \@realign, action => $action );
        }
        if ($ws eq 'bibliocontrol') {   
            $template = $self->get_template({ file => 'bibliocontrol.tt' });
            my $rcr = $cgi->param('rcr');
            if ($rcr) {
                $template->param( rcr => $rcr );
                $template->param( bibs => $self->get_bibliocontrol($rcr) );
            }
            else {      
                $template->param( rcr_select => $c->{iln}->{rcr_array} );
            }
        }
        elsif ($ws eq 'algo') {
            $template = $self->get_template({ file => 'algo.tt' });
            my @rcr = $cgi->multi_param('rcr');
            my @tdoc = $cgi->multi_param('tdoc');
            if (@rcr) {
                $template->param( rcr_hash => $c->{iln}->{rcr_hash} );
                $template->param( tdoc_hash => $conf->{algo}->{tdoc}->{get_hash}->() );
                $template->param( recs => $self->get_algo(\@rcr, \@tdoc) );
            }
            else {
                $template->param( rcr_select => $c->{iln}->{rcr_array} );
                $template->param( tdoc_select => $conf->{algo}->{tdoc}->{get_array}->() );
            }
        }
    }
    else {
        $template = $self->get_template({ file => 'home.tt' });
        my $cache = $self->{cache};
        my $key = "abesws-home";
        my $markdown = $cache->get_from_cache($key);
        unless ($markdown) {
            my $text = $self->mbf_read("home.md");
            utf8::decode($text);
            my $response = Pithub::Markdown->new->render(
                data => {
                    text => $text,
                    context => "github/gollum",
                },
            );
            $markdown = $response->raw_content;
            utf8::decode($markdown);
            $cache->set_in_cache($key, $markdown, { expiry => 3600 });
        }
        $template->param( markdown => $markdown );
    }
    $template->param( c => $self->config() );
    $template->param( WS => $ws ) if $ws;
    $self->output_html( $template->output() );
}

sub get_biblio_per_ppn {
    my ($self, $ppn) = @_;

    my $sth = $self->{args}->{sth_biblio};
    unless ($sth) {
        my $c = $self->config();
        my $ppn_field = $c->{iln}->{ppn};
        my $query = "
            SELECT
                biblionumber,
                title
            FROM
                biblio
            LEFT JOIN biblioitems USING(biblionumber)
            WHERE $ppn_field = ?
        ";
        my $dbh = C4::Context->dbh;
        $sth = $dbh->prepare($query);
    }
    $sth->execute($ppn);
    my ($biblionumber, $title) = $sth->fetchrow_array;
    $title =~ s/\x88|\x89|\x98|\x9c//g;
    {
        biblionumber => $biblionumber,
        title        => $title,
    };
}

sub get_bibliocontrol {
    my ($self, $rcr) = @_;

    my $c   = $self->config();
    my $api = $c->{url}->{api};
    my $ua  = $self->{ua} ||= Mojo::UserAgent->new;
    my $url = "$api/bibliocontrol/$rcr";
    # Le service web renvoie un fichier en UTF-16LE
    my $res = $ua->get($url)->result->body;
    $res = decode('UTF-16LE', $res);
    my @lines = split /\n/, $res;
    shift @lines;
    my %per_ppn;
    my %errors;
    {
        my @err = @{$conf->{bibliocontrol}->{errors}};
        for (my $i=0; $i < @err; $i++) {
            $errors{$err[$i]} = $i;
        }
    }

    for my $line (@lines) {
        $line =~ s/\r$//;
        my ($ppn, undef, $what) = split /\t/, $line;
        $ppn = substr($ppn, 2, length($ppn)-3);
        $per_ppn{$ppn} ||= [0, 0, 0];
        $per_ppn{$ppn}->[$errors{$what}] = 1;
    }
    my @bibs = map {
        my $ppn = $_;
        my $bib = $self->get_biblio_per_ppn($ppn);
        $bib->{ppn} = $ppn;
        $bib->{ctrl} = $per_ppn{$ppn};
        $bib;
    } keys %per_ppn;
    # Tri par biblionumber
    @bibs = sort { $b->{ppn} <=> $a->{ppn} } @bibs;
    return \@bibs;
}

sub get_algo {
    my ($self, $rcr, $tdoc) = @_;

    my $c   = $self->config();
    my $api = $c->{url}->{algo};
    my $ua  = $self->{ua} ||= Mojo::UserAgent->new;
    my $url = "$api?rcr=" . join(',', @$rcr) . '&typdoc=' . join(',', @$tdoc);
    my $res = $ua->get($url)->result->body;
    #$res = decode('UTF-16LE', $res);
    my @lines = split /\n/, $res;
    shift @lines; shift @lines; shift @lines;
    my %per_ppn;
    for my $line (@lines) {
        $line =~ s/\r$//;
        my ($ppn, undef, $rcr, undef, $date, $where, $tdoc) = split /\t/, $line;
        $where = substr($where, 1);
        $per_ppn{$ppn} ||= {
            rcr  => $rcr,
            tdoc => $tdoc,
            date => substr($date, 0, 10), where => [] };
        push @{ $per_ppn{$ppn}->{where} }, $where;
    }

    my @recs = map {
        my $ppn = $_;
        my $rec = $per_ppn{$ppn};
        $rec->{ppn} = $ppn;
        my $bib = $self->get_biblio_per_ppn($ppn);
        $rec->{title} = $bib->{title};
        $rec->{biblionumber} = $bib->{biblionumber};
        $rec;
    } keys %per_ppn;
    return \@recs;
}

sub realign {
    my $self = shift;

    my ($from, $to, $doit) = (1, 999999999, 0);
    while (@_) {
        $_ = shift;
        if    ( /^[0-9]*$/ )            { $from = $to = $_;        }
        elsif ( /^([0-9]+)-$/ )         { $from = $1;              }
        elsif ( /^-([0-9]+)$/ )         { $to = $1;                }
        elsif ( /^([0-9]+)-([0-9]+)$/ ) { ($from, $to) = ($1, $2); }
        elsif ( /doit/i )               {  $doit = 1;              }
    }
    say "from: $from - to: $to";

    my $start = DateTime->now;

    my $plugin = Koha::Plugin::AbesWS->new({
        enable_plugins => 1,
    });

    my $cache = $self->{cache};

    my ($biblionumber, $record);
    my $sth = C4::Context->dbh->prepare(
        "SELECT biblionumber, metadata FROM biblio_metadata
         WHERE biblionumber BETWEEN $from AND $to");
    $sth->execute();
    my $sth_update = C4::Context->dbh->prepare("
        UPDATE biblio_metadata
        SET metadata=?
        WHERE biblionumber=?
    ");

    my $ua  = Mojo::UserAgent->new;
    my $actions = {};
    my @idx_ids;
    my $idx_indexer = Koha::SearchEngine::Indexer->new({ index => $Koha::SearchEngine::BIBLIOS_INDEX });
    my $idx_submit = sub {
        return unless @idx_ids;
        $idx_indexer->index_records(\@idx_ids, "specialUpdate", "biblioserver");
        @idx_ids = ();
    };
    my $idx_add = sub {
        push @idx_ids, shift;
        $idx_submit->() if @idx_ids == 1000;
    };
    while ( ($biblionumber, $metadata) = $sth->fetchrow ) {
        say $biblionumber;
        my $record = MARC::Moose::Record::new_from($metadata, 'Marcxml');
        my $modified = 0;
        FIELDS_LOOP:
        for my $field ( $record->field('7..|600|601') ) {
            my $ppn = $field->subfield('3');
            next unless $ppn;
            my $xml = $cache->get_from_cache($ppn);
            #say "PPN $ppn" if $xml;
            my ($url, $res, $action, $new_ppn);
            unless ($xml) {
                $url = "https://www.idref.fr/$ppn.xml";
                $res = $ua->get($url)->result;
            }
            #say Dump($res);
            if ($xml || $res->is_success || $res->code eq '301') {
                if (!$xml && $res->code eq '301') {
                    # PPN fusionné à un autre PPN
                    $xml = undef;
                    $url = $res->headers->location;
                    $url =~ /\.fr\/(.+)\.xml$/;
                    $new_ppn = $1;
                    $res = $ua->get($url)->result;
                }
                next if !$xml && $res->headers->content_type !~ /xml/;
                unless ($xml) {
                    $xml = $res->body;
                    $cache->set_in_cache($ppn, $xml, { expiry => 5184000 });
                }
                my $auth = MARC::Moose::Record::new_from($xml, 'marcxml');
                next unless $xml;
                if ($new_ppn) {
                    $action = {
                        action => 'merge',
                        ppn => $ppn,
                        avant => $field->as_formatted,
                    };
                    for (@{$field->subf}) {
                        $_->[1] = $new_ppn if $_->[0] eq '3';
                    }
                    $action->{apres} = $field->as_formatted;
                    push @{$actions->{$biblionumber}}, $action;
                    $action = undef;
                    $modified = 1;
                }
                my $field_match = join(' ',
                    map { $_->[1] } grep { $_->[0] =~ /[abcdfg]/ } @{$field->subf});
                # Récupération de la vedette, en écriture latine (frefre en $8)
                my @heading = $auth->field('2..');
                my $heading;
                if (@heading > 1) {
                    for my $field (@heading) {
                        my $lang = $field->subfield('8') || '';
                        $heading = $field if $lang eq 'frefre';
                        if (my $ecriture = $field->subfield('7')) {
                            $heading = $field if substr($ecriture, 4, 2) eq 'ba';
                        }
                    }
                }
                $heading = $heading[0] unless $heading;
                unless ($heading) {
                    say "PAS DE VEDETTE :";
                    say $auth->as('text');
                    exit;
                }
                my $heading_match = join(' ',
                    map { $_->[1] } grep { $_->[0] =~ /[abcdfg]/ }  @{$heading->subf} );
                if ($field_match ne $heading_match) {
                    #say $field->as_formatted;
                    #say $heading->as_formatted;
                    $action = {
                        action => 'modify',
                        ppn => $new_ppn || $ppn,
                        avant => $field->as_formatted,
                    };
                    my @subf = grep { $_->[0] !~ /[abcdfg]/ } @{$field->subf};
                    for (@{$heading->subf}) {
                        next if $_->[0] !~ /[abcdfg]/;
                        push @subf, $_;
                    }
                    $field->subf( \@subf );
                    $action->{apres} = $field->as_formatted;
                }
            }
            else {
                # $3 supprimé => ne pas le garder dans la notice...
                $action = {
                    action => 'del',
                    ppn => $ppn,
                    avant => $field->as_formatted,
                };
                $field->subf( [ grep { $_->[0] !~ '3' } @{$field->subf} ] );
                $action->{apres} = $field->as_formatted;
                $modified = 1;
            }
            if ($action) {
                push @{$actions->{$biblionumber}}, $action;
                $modified = 1;
            }
        }
        if ($modified && $doit) {
            $sth_update->execute($record->as('marcxml'), $biblionumber);
            $idx_add->($biblionumber);
        }
    }
    $idx_submit->();

    my $table_name = $self->get_qualified_table_name('action');
    C4::Context->dbh->do(qq{
        INSERT INTO $table_name (type, result, start, end)
        VALUES (?, ?, ?, ?)
    }, undef, 'realign', to_json($actions), $start, DateTime->now );
}


sub autorite {
    my $self = shift;

    my ($biblionumber, $record);
    my $sth = C4::Context->dbh->prepare(
        "SELECT biblionumber, metadata FROM biblio_metadata
         ORDER BY biblionumber");
    $sth->execute();
    my %ppn;
    while ( ($biblionumber, $metadata) = $sth->fetchrow ) {
        #say $biblionumber;
        my $record = MARC::Moose::Record::new_from($metadata, 'Marcxml');
        FIELDS_LOOP:
        for my $field ( $record->field('7..|600|601') ) {
            my $ppn = $field->subfield('3');
            next unless $ppn;
            next if $ppn{$ppn};
            $ppn{$ppn} = 1;
        }
    }
    open my $fh, '>', 'ppn.txt';
    say join("\n", keys %ppn);
}


sub intranet_js {
    my $self = shift;
    my $js_file = $self->get_plugin_http_path() . "/abesws.js";
    my $c = encode_json($self->config());
    return <<EOS;
<script>
\$(document).ready(() => {
  \$.getScript("$js_file")
    .done(() => \$.abesWs($c));
});
</script>
EOS
}

sub opac_js {
  shift->intranet_js();
}

sub api_namespace {
    my ($self) = $_;
    return 'abesws';
}

sub api_routes {
    my $self = shift;
    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);
    return $spec;
}

sub install() {
    my ($self, $args) = @_;
    my $name = $self->get_qualified_table_name('action');
    my $dbh = C4::Context->dbh;
    $dbh->do("DROP TABLE IF EXISTS $name");
    $dbh->do(qq{
        CREATE TABLE $name (
            id SERIAL,
            type VARCHAR(80),
            result JSON,
            start TIMESTAMP NULL,
            end TIMESTAMP NULL,
            PRIMARY KEY (id),
            INDEX (type)
        )
    });
}

sub upgrade {
    my ($self, $args) = @_;

    my $dt = DateTime->now();
    $self->store_data( { last_upgraded => $dt->ymd('-') . ' ' . $dt->hms(':') } );

    return 1;
}

sub uninstall() {
    my ($self, $args) = @_;
}

1;
