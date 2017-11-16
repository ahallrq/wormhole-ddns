package Wormhole::Route::Help;

use strict;
use warnings;

use lib "..";
use Wormhole::Config;
use Wormhole::Util::Checks qw(check_params check_method);

sub get_help {
    my $req = shift;

    my $c_method = check_method($req);
    if (!defined $c_method) {
        my $c_params = check_params($req, ("key")); 
        if (!defined $c_params && $req->body_parameters->get("key") eq $Wormhole::Config::admin_key) {
            my $res = $req->new_response(200, [],
                "-- Wormhole DynDNS Admin help --\n" .
                "[POST] /create <key> <subdomain>           - Create a subdomain with a random key\n" .
                "[POST] /modify <key> <subdomain> <ip4/ip6> - Manually assign an address to a subdomain\n" .
                "[POST] /delete <key> <subdomain>           - Delete a subdomain\n" .
                "[POST] /lock   <key> <subdomain> <1/0>     - Modify lock state of a subdomain\n" .
                "[POST] /chgkey <key> <subdomain>           - Generate a new random key for a subdomain\n" .
                "[POST] /list   <key> <subdomain>           - List all subdomains, their ips and last update\n" .
                "[POST] /help   <key>                       - Display admin help\n");
            return $res->finalize;
        }
    }

    my $res = $req->new_response(200, [], 
        "-- Wormhole DynDNS help --\n" .
        "[POST] /update <key> <subdomain> - Update your subdomain\n" .
        "[POST] /clear  <key> <subdomain> - Clear your subdomain\n" .
        "[ GET] /help                     - Display help\n");
    return $res->finalize;
}

1;