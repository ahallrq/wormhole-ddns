package Wormhole::Route::LockSub;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(lock_subdomain);

use lib "..";
use Wormhole::Util::Checks qw(check_params check_key check_method subdomain_exists valid_subdomain);
use Wormhole::Util::Database;

sub lock_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain", "state")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $Wormhole::Config::admin_key); if (defined $c_key) { return $c_key; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }

    my @states = ("unlock", "lock");
    my $lock_state = $req->body_parameters->get("state");
    my $subdomain = $req->body_parameters->get("subdomain");
    my $time = time;

    if ($lock_state ne '1' && $lock_state ne '0') {
        my $res = $req->new_response(400, [], 
            "Invalid state specified. Use '1' for lock and '0' for unlock\n");
        return $res->finalize;
    }

    my $s_res = $Wormhole::Util::Database::DDNS_DB_UPD_LCK->execute($lock_state, $subdomain);

    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully $states[$lock_state]ed subdomain \"$subdomain.$Wormhole::Config::NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to $states[$lock_state] subdomain \"$subdomain.$Wormhole::Config::NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    }
}

1;