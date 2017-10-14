package listsub;

use strict;
use warnings;

use lib "..";
use conf;
use checks qw(check_params check_method check_key);
use database;

sub list_subdomains {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $conf::admin_key); if (defined $c_key) { return $c_key; }

    my @states = ("unlocked", "locked");

    my $restext = "-- Wormhole DynDNS Subdomains --\n";
    $database::DDNS_DB_SEL_ALL->execute;
    my $rowcount = 0;
    while (my @row = $database::DDNS_DB_SEL_ALL->fetchrow_array) {
        $rowcount += 1;
        my $time = localtime $row[5];
        my $lockstate = $row[4];
        $restext .= "$row[0].$conf::NAMESERVER_DNS_ZONE:\n├── Key: $row[1]\n├── State: $states[$lockstate]\n├── Updated: $time\n" .
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