package createsub;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(create_subdomain);

use lib "..";
use checks qw(check_params check_key check_method subdomain_exists valid_subdomain);
use util qw(rand_pass);
use database;

sub create_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $conf::admin_key); if (defined $c_key) { return $c_key; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 0) { 
        my $res = $req->new_response(404, [], "The specified subdomain already exists.\n"); 
        return $res->finalize;
    }

    my $subdomain = $req->body_parameters->get("subdomain");
    my $subdomain_key = rand_pass(64);
    my $time = time;

    my $s_res = $database::DDNS_DB_INS->execute($subdomain, $subdomain_key, "(unset)", "(unset)", 0, $time, 0, 0);
    
    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully created subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\"\nKey: $subdomain_key\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to create subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    }
}

1;