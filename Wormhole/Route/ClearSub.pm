package Wormhole::Route::ClearSub;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(clear_ddns);

use lib "..";
use Wormhole::Util::Checks qw(check_params check_key check_method subdomain_exists valid_subdomain);
use Wormhole::Util::MiscUtils qw(ip_record_type execute_ddns);
use Wormhole::Util::Database;
use Net::DNS;

sub clear_ddns {
    my $req = shift;

    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }
    my $c_key = check_key($req, $subdomain_r[1]); if (defined $c_key) { return $c_key; }

    my $query = $req->body_parameters;
    my $subdomain = $query->get('subdomain');
    my $address   = $req->address;
    my $rec_type  = ip_record_type($address);

    if ($subdomain_r[4] == 1) {
        my $res = $req->new_response(401, [], 
            "The subdomain cannot be cleared because it is currently locked.\n" .
            "Please contact the administrator for assistance.\n"); 
        return $res->finalize;
    }

    my $dns_update = new Net::DNS::Update($Wormhole::Config::NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$Wormhole::Config::NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->sign_tsig($Wormhole::Config::NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
   	my $res = $req->new_response(400, [], 
       "An attempt to clear $subdomain.$Wormhole::Config::NAMESERVER_DNS_ZONE failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        $Wormhole::Util::Database::DDNS_DB_UPD_ADR->execute("(unset)", "(unset)", $time, $subdomain_r[0]);
        my $res = $req->new_response(200, [], 
            "Successfully cleared $subdomain.$Wormhole::Config::NAMESERVER_DNS_ZONE.\n"); return $res->finalize;
    }
}

1;