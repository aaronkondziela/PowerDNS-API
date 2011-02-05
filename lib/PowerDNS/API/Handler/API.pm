package PowerDNS::API::Handler::API;
use Dancer ':syntax';
use Moose;
extends 'PowerDNS::API::Handler';

use JSON qw(encode_json);
use namespace::clean;

sub schema { return PowerDNS::API::schema() }

prefix '/api';

set serializer => 'JSONC';

use Dancer::Plugin::REST;

get '/domain/:id?' => sub {

    my $id = params->{id} || '';
    
    {
        my $x = "getting domain: [$id]";
        $Test::More::VERSION ? Test::More::diag($x) : debug($x);
    }

    if ($id eq '') {
        # TODO: only do the appropriate accounts
        my $domains = schema->domain->search();
        my $data = [];
        while (my $domain = $domains->next) {
            push @$data, $domain;
        }
        return status_ok({ domains => $data });
    }

    # we're just working on one domain
    my $domain = schema->domain->find({ name => $id })
      or return status_not_found("domain doesn't exist");

    return status_ok({ domain => $domain,
                       records => _records($domain)
                     }
                    );

};

sub _records {
    my ($domain, $options) = @_;

    my @args = qw(name type content);
    my %args = map { $_ => $options->{$_} } grep { defined $options->{$_} } @args;
    
    if (defined $args{name}) {
        $args{name} = $domain->clean_hostname( $args{name} );
    }
    
    my $records = schema->record->search({ %args,
                                           domain_id => $domain->id
                                         });

    my $data = $records ? { records => [ $records->all ] } : undef;

   return $data;

}

sub _soa_fields {
    return qw(primary hostmaster serial refresh retry expire default_ttl);
}

put '/domain/:domain' => sub {

    my $name = params->{domain} or return status_bad_request();
    # check permissions

    {
        my $domain = schema->domain->find({ name => $name });
        return status_conflict("domain exists") if $domain;
    }

    my $data = {};
    for my $f (qw(master type)) {
        $data->{$f} = params->{$f};
    }
    $data->{name} = $name;
    $data->{type} = 'MASTER'
      unless ($data->{type} and uc $data->{type} eq 'SLAVE');

    $data->{type} = uc $data->{type};

    if ($data->{type} eq 'SLAVE') {
        return status_bad_request('master parameter required for slave domains')
          unless $data->{master};
    }

    my $domain = schema->domain->create($data);

    my $soa = { };

    for my $s (_soa_fields()) {
        $soa->{$s} = params->{$s};
    }

    my $soa_data = join " ", map { $soa->{$_} || '' } _soa_fields();

    schema->record->create({ domain_id => $domain->id,
                             name      => $domain->name,
                             type      => 'SOA',
                             content   => $soa_data,
                             ttl       => 7200,
                             change_date => time,
                           })
      unless $domain->type eq 'SLAVE';

    return status_created({ domain => $domain });

};

post '/domain/:domain' => sub {

    my $domain_name = params->{domain} or return status_bad_request();
    
    # check permissions

    my $domain = schema->domain->find({ name => $domain_name })
      or return status_not_found("domain not found");

    # TODO: start transaction

    my $data = {};
    for my $f (qw(master type)) {
        next unless defined params->{$f};
        $domain->$f(uc params->{$f});
    }
    if ($domain->type eq 'SLAVE') {
        return status_bad_request("master required for slave domains")
          unless $domain->master;
    }

    # TODO: increment TTL

    $domain->update;

    # TODO: commit

    return status_ok({ domain => $domain });
};

put '/record/:domain/:id' => sub {
    my $domain_name = params->{domain} or return status_bad_request();
    my $record_id   = params->{id} or return status_bad_request("record id required");

    my $domain = schema->domain->find({ name => $domain_name })
      or return status_not_found("domain not found");

    my $record = schema->record->find({ id => $record_id, domain_id => $domain->id })
      or return status_not_found("record not found");

    # TODO:
      # parse parameters as approprate for each type
      # support specific names per data type as appropriate (rather than just 'content')

    for my $f ( qw( type name content ttl prio ) ) {
        $record->$f( params->{$f} ) if defined params->{$f};
    }

    $record->update;

    return status_accepted( { record => $record, domain => $domain } );

};

post '/record/:domain' => sub {

    # check permissions
    
    my $domain_name = params->{domain} or return status_bad_request();

    my $domain = schema->domain->find({ name => $domain_name })
      or return status_not_found("domain not found");

    for my $f (qw( type name content ) ) {
        defined params->{$f}
          or return status_bad_request("$f is required")
    }

    my $data = {};
    for my $f (qw( type name content ttl prio ) ) {
        next unless defined params->{$f};
        $data->{$f} = params->{$f};
    }
    $data->{type} = uc $data->{type};
    $data->{name} = $domain->clean_hostname( $data->{name} );
    unless (defined $data->{ttl}) {
        $data->{ttl} = $data->{type} eq 'NS' ? 86400 : 7200;
    }

    $data->{change_date} = time;

    my $record = $domain->add_to_records($data);

    # TODO: bump serial

    return status_created({ domain => $domain, record => $record } );

};

del '/record/:domain/:id' => sub {

    my $domain_name = params->{domain} or return status_bad_request();
    my $record_id   = params->{id} or return status_bad_request("record id required");

    my $domain = schema->domain->find({ name => $domain_name })
      or return status_not_found("domain not found");

    my $record = schema->record->find({ id => $record_id, domain_id => $domain->id })
      or return status_not_found("record not found");

    # check permissions

    $record->delete;

    return status_ok({ message => "record deleted", domain => $domain });

};

1;
