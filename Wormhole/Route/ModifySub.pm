package Wormhole::Route::ModifySub;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(modify_subdomain);

use lib "..";
use Wormhole::Util::Checks qw(check_params check_key check_method subdomain_exists valid_subdomain);
use Wormhole::Util::MiscUtils qw(ip_record_type execute_ddns);
use Wormhole::Util::Database;
use Net::DNS;

sub modify_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain", "ip")); if (defined $c_params) { return $c_params; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }
    my $c_key = check_key($req, $Wormhole::Config::admin_key); if (defined $c_key) { return $c_key; }
    
    my $subdomain = $req->body_parameters->get('subdomain');
    my $address   = $req->body_parameters->get('ip');
    my $ttl       = 2;
    my $rec_type  = ip_record_type($address);
    if (!defined $rec_type) {
        my $res = $req->new_response(400, [], "Invalid IP address specified.\n"); return $res->finalize;
    }

    my $dns_update = new Net::DNS::Update($Wormhole::Config::NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$Wormhole::Config::NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->push(update => rr_add("$subdomain.$Wormhole::Config::NAMESERVER_DNS_ZONE. $ttl $rec_type $address"));
    $dns_update->sign_tsig($Wormhole::Config::NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
        my $res = $req->new_response(400, [], "Modfication failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        if ($rec_type eq "A") {
            $Wormhole::Util::Database::DDNS_DB_UPD_ADR->execute($address, $subdomain_r[3], $time, $subdomain_r[0]);
        } elsif ($rec_type eq "AAAA") {
            $Wormhole::Util::Database::DDNS_DB_UPD_ADR->execute($subdomain_r[2], $address, $time, $subdomain_r[0]);
        }
        
        my $res = $req->new_response(200, [], "Modfication successful.\n"); return $res->finalize;
    }
}

1;