package Wormhole::Route::ChgKey;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(chgkey_subdomain);

use lib "..";
use Wormhole::Util::Checks qw(check_params check_key check_method subdomain_exists valid_subdomain);
use Wormhole::Util::MiscUtils qw(rand_pass);
use Wormhole::Util::Database;

sub chgkey_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $Wormhole::Config::admin_key); if (defined $c_key) { return $c_key; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }

    my $subdomain = $req->body_parameters->get("subdomain");

    my $subdomain_key = rand_pass(64);

    my $s_res = $Wormhole::Util::Database::DDNS_DB_UPD_KEY->execute($subdomain_key, $subdomain);

    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully regenerated key for subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\"\n" .
            "Key: $subdomain_key\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to regenerate key for subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    }
}

1;