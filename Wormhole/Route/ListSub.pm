package Wormhole::Route::ListSub;

use strict;
use warnings;

use lib "..";
use Wormhole::Config;
use Wormhole::Util::Checks qw(check_params check_method check_key);
use Wormhole::Util::Database;

sub list_subdomains {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $Wormhole::Config::admin_key); if (defined $c_key) { return $c_key; }

    my @states = ("unlocked", "locked");

    my $restext = "-- Wormhole DynDNS Subdomains --\n";
    $Wormhole::Util::Database::DDNS_DB_SEL_ALL->execute;
    my $rowcount = 0;
    while (my @row = $Wormhole::Util::Database::DDNS_DB_SEL_ALL->fetchrow_array) {
        $rowcount += 1;
        my $time = localtime $row[5];
        my $lockstate = $row[4];
        $restext .= "$row[0].$Wormhole::Config::NAMESERVER_DNS_ZONE:\n├── Key: $row[1]\n├── State: $states[$lockstate]\n├── Updated: $time\n" .
                    "├── IPv4: $row[2]\n└── IPv6: $row[3]\n\n";
    }
    
    if (!$rowcount) {
        $restext .= "No subdomains found.\n";
    } else {
        $restext .= "Successfully listed $rowcount subdomain(s).\n";
    }

    my $res = $req->new_response(200, [], $restext);
    return $res->finalize;
}

1;