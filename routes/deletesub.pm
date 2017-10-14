package deletesub;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(delete_subdomain);

use lib "..";
use checks qw(check_params check_key check_method subdomain_exists valid_subdomain);
use util qw(execute_ddns);
use database;
use Net::DNS;

sub delete_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $conf::admin_key); if (defined $c_key) { return $c_key; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }

    my $subdomain = $req->body_parameters->get("subdomain");

    my $dns_update = new Net::DNS::Update($conf::NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$conf::NAMESERVER_DNS_ZONE. A"));
    $dns_update->push(update => rr_del("$subdomain.$conf::NAMESERVER_DNS_ZONE. AAAA"));
    $dns_update->sign_tsig($conf::NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);

    if (!$r_code) {
   	my $res = $req->new_response(400, [], 
        "Failed to delete subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\" from nameserver.\n");
        return $res->finalize;
    }

    my $s_res = $database::DDNS_DB_DEL->execute($subdomain);
    
    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully deleted subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to delete subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\" from database.\n");
        return $res->finalize;
    }
}

1;