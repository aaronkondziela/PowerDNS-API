use Test::More;
use strict;
use warnings;
use Data::Dump qw(pp);

use Test::Mojo;
my $t = Test::Mojo->new('PowerDNS::API');

$Carp::Verbose = 1;

use lib 't';
use TestUtils;

$TestUtils::t = $t;

my $domain = test_domain_name;

my $schema = $t->app->schema;
ok(my $account  = setup_user, 'setup account');
ok(my $account2 = setup_user, 'setup account 2');

ok(my $r = api_call(PUT => "domain/$domain", { hostmaster => 'ask@example.com', user => $account }), 'setup new domain');
$t->status_is(201, "ok, created $domain");
ok( $r->{domain}->{soa}->{serial}, "got serial");

ok($r = api_call(GET => "domain/$domain", { user => $account }), "Get domain");
$t->status_is(200);
is($r->{records}->[0]->{type}, 'SOA', 'has soa record');
is($r->{records}->[0]->{hostmaster}, 'ask@example.com', 'soa hostmaster');
#diag pp($r->{records});

ok($r = api_call(PUT => "domain/$domain", { user => $account }), 'setup duplicate new domain');
$t->status_is(409);

$domain = uc test_domain_name;
ok($r = api_call(PUT => "domain/$domain", { user => $account }), "setup new domain (uppercase): $domain");
$t->status_is(201);
is($r->{domain}->{name}, lc $domain, "got setup as lowercase domain");

ok($r = api_call(PUT => "domain/sub2.$domain", { user => $account2 }), 'setup sub-domain with another account');
$t->status_is(403, 'forbidden');

ok($r = api_call(PUT => "domain/sub.$domain", { user => $account }), 'setup sub-domain with the same account');
$t->status_is(201, 'created');

#diag pp($r);

ok($account->delete, 'deleted account again');
ok($account2->delete, 'deleted second account');

done_testing();
exit;
