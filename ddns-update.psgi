#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper qw(Dumper);
$Data::Dumper::Sortkeys = 1;

use DBI;
use Plack::Request;
use Net::DNS;
use Regexp::Common qw /net/;

my $admin_key = "<insert key here>";
my @key_char_set = ("A".."Z", "a".."z", "0".."9");

my $NAMESERVER_DNSSEC_KEY = "/path/to/a/dnssec/key";
my $NAMESERVER_DNS_ZONE = "ddns.example.org";
#my @NAMESERVER_NS_LIST = ("ns1.ddns.example.org", "ns2.ddns.example.org");
my $NAMESERVER = "ns1.ddns.example.org";

my $DDNS_DB = DBI->connect("dbi:SQLite:ddns.db","","") or die "Could not connect to database\n";
my ($DDNS_DB_INS, $DDNS_DB_SEL_ALL, $DDNS_DB_SEL, $DDNS_DB_UPD_ADR);
my ($DDNS_DB_DEL, $DDNS_DB_UPD_ATT, $DDNS_DB_UPD_KEY, $DDNS_DB_UPD_LCK);

while (1) {
    $DDNS_DB_INS = eval { $DDNS_DB->prepare('INSERT INTO subdomains VALUES (?,?,?,?,?,?,?,?)') };
    $DDNS_DB_UPD_ATT = eval { $DDNS_DB->prepare('UPDATE subdomains SET attempt_time = ?, attempt_count = ? WHERE subdomain = ?') };
    $DDNS_DB_UPD_KEY = eval { $DDNS_DB->prepare('UPDATE subdomains SET key = ? WHERE subdomain = ?') };
    $DDNS_DB_UPD_ADR = eval { $DDNS_DB->prepare('UPDATE subdomains SET ipv4 = ?, ipv6 = ?, update_time = ? WHERE subdomain = ?') };
    $DDNS_DB_UPD_LCK = eval { $DDNS_DB->prepare('UPDATE subdomains SET lock = ? WHERE subdomain = ?') };
    $DDNS_DB_DEL = eval { $DDNS_DB->prepare('DELETE FROM subdomains WHERE subdomain = ?') };
    $DDNS_DB_SEL_ALL = eval { $DDNS_DB->prepare('SELECT * FROM subdomains') };
    $DDNS_DB_SEL = eval { $DDNS_DB->prepare('SELECT * FROM subdomains WHERE subdomain = ?') };
    last if $DDNS_DB_INS && $DDNS_DB_UPD_ATT && $DDNS_DB_UPD_KEY && $DDNS_DB_UPD_ADR;
    last if $DDNS_DB_DEL && $DDNS_DB_SEL && $DDNS_DB_SEL_ALL && $DDNS_DB_UPD_LCK;

    warn "Creating table 'subdomains'\n";
    $DDNS_DB->do('CREATE TABLE subdomains (subdomain varchar(255) PRIMARY KEY, key varchar(255), ' .
                 'ipv4 varchar(255), ipv6 varchar(255), lock int, update_time int, ' .
                 'attempt_time int, attempt_count int);') or
        die("Failed to create table in database.\n");
}

my %routes = (
    "/create" => \&create_subdomain,
    "/modify" => \&modify_subdomain,
    "/delete" => \&delete_subdomain,
    "/lock" => \&lock_subdomain,
    "/chgkey" => \&chgkey_subdomain,
    "/list" => \&list_subdomains,
    "/help" => \&get_help,
    "/update" => \&update_ddns,
    "/clear" => \&clear_ddns,
);

sub rand_pass {
    my $len = shift;
    my $pass;

    for (my $i=0; $i < $len; $i++) {
        srand; $pass .= $key_char_set[rand @key_char_set];
    }
    
    return $pass;
}

sub ip_record_type {
    my $addr = shift;
    my $type = undef;
    if ($addr =~ /^$RE{net}{IPv4}$/) {
        $type = "A";
    }
    elsif ($addr =~ /^$RE{net}{IPv6}$/) {
        $type = "AAAA";
    }
    return $type;
}

sub check_params {
    my ($req, @param_list) = @_;
    
    my $query = $req->body_parameters;

    foreach my $param (@param_list) {
        my $tmp = $query->get($param);
        
        if (!defined $tmp) {
            my $res = $req->new_response(400, [], 
                    "One or more required parameters is missing from the request.\n" .
                    "Check the documentation for more informaion.\n");
            return $res->finalize;
        }
    }

    return undef;
}

sub check_key {
    my ($req, $valid_key) = @_;
    
    my $query     = $req->body_parameters;
    my $api_key   = $query->get('key');
    
    if ($api_key ne $valid_key) {
	    my $res = $req->new_response(403, [], 
            "An invalid key has been supplied and as a result access has been denied.\n");
	    return $res->finalize;
    }
    
    return undef;
}

sub check_method {
    my $req = shift;

    if ($req->method ne 'POST') {
        my $res = $req->new_response(405, [], "Only POST requests are supported.\n");
        return $res->finalize;
    }
    
    return undef;
}

sub subdomain_exists {
    my $req = shift;

    $DDNS_DB_SEL->execute($req->body_parameters->get('subdomain'));
    my @result = $DDNS_DB_SEL->fetchrow_array;
    if (!@result) {
        my @res = ($req->new_response(404, [], "The specified subdomain was not found.\n"));
        return @res;
    }
    
    return @result;
}

sub valid_subdomain {
    my $req = shift;

    my $subdomain = $req->body_parameters->get('subdomain');

    if ($subdomain !~ m/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/) {
        my $res = $req->new_response(400, [], 
                "Requested subdomain contains one or more invalid characters.\n" . 
                "Subdomains must consist of alphanumeric characters and hyphens." .
                "Furthermore they must not start or end with hyphens.\n");
        return $res->finalize;
    }
    
    return undef;
}

sub create_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $admin_key); if (defined $c_key) { return $c_key; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 0) { 
        my $res = $req->new_response(404, [], "The specified subdomain already exists.\n"); 
        return $res->finalize;
    }

    my $subdomain = $req->body_parameters->get("subdomain");
    my $subdomain_key = rand_pass(64);
    my $time = time;

    my $s_res = $DDNS_DB_INS->execute($subdomain, $subdomain_key, "(unset)", "(unset)", 0, $time, 0, 0);
    
    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully created subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\"\nKey: $subdomain_key\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to create subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    }
}

sub delete_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $admin_key); if (defined $c_key) { return $c_key; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }

    my $subdomain = $req->body_parameters->get("subdomain");

    my $dns_update = new Net::DNS::Update($NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$NAMESERVER_DNS_ZONE. A"));
    $dns_update->push(update => rr_del("$subdomain.$NAMESERVER_DNS_ZONE. AAAA"));
    $dns_update->sign_tsig($NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);

    if (!$r_code) {
   	my $res = $req->new_response(400, [], 
        "Failed to delete subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\" from nameserver.\n");
        return $res->finalize;
    }

    my $s_res = $DDNS_DB_DEL->execute($subdomain);
    
    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully deleted subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to delete subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\" from database.\n");
        return $res->finalize;
    }
}

sub list_subdomains {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $admin_key); if (defined $c_key) { return $c_key; }

    my @states = ("unlocked", "locked");

    my $restext = "-- Wormhole DynDNS Subdomains --\n";
    $DDNS_DB_SEL_ALL->execute;
    my $rowcount = 0;
    while (my @row = $DDNS_DB_SEL_ALL->fetchrow_array) {
        $rowcount += 1;
        my $time = localtime $row[5];
        my $lockstate = $row[4];
        $restext .= "$row[0].$NAMESERVER_DNS_ZONE:\n├── Key: $row[1]\n├── State: $states[$lockstate]\n├── Updated: $time\n" .
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

sub lock_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain", "state")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $admin_key); if (defined $c_key) { return $c_key; }
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

    my $s_res = $DDNS_DB_UPD_LCK->execute($lock_state, $subdomain);

    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully $states[$lock_state]ed subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to $states[$lock_state] subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    }
}

sub chgkey_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $admin_key); if (defined $c_key) { return $c_key; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }

    my $subdomain = $req->body_parameters->get("subdomain");

    my $subdomain_key = rand_pass(64);

    my $s_res = $DDNS_DB_UPD_KEY->execute($subdomain_key, $subdomain);

    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully regenerated key for subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\"\n" .
            "Key: $subdomain_key\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to regenerate key for subdomain \"$subdomain.$NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    }
}

sub modify_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain", "ip")); if (defined $c_params) { return $c_params; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }
    my $c_key = check_key($req, $admin_key); if (defined $c_key) { return $c_key; }
    
    my $subdomain = $req->body_parameters->get('subdomain');
    my $address   = $req->body_parameters->get('ip');
    my $ttl       = 2;
    my $rec_type  = ip_record_type($address);
    if (!defined $rec_type) {
        my $res = $req->new_response(400, [], "Invalid IP address specified.\n"); return $res->finalize;
    }

    my $dns_update = new Net::DNS::Update($NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->push(update => rr_add("$subdomain.$NAMESERVER_DNS_ZONE. $ttl $rec_type $address"));
    $dns_update->sign_tsig($NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
        my $res = $req->new_response(400, [], "Modfication failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        if ($rec_type eq "A") {
            $DDNS_DB_UPD_ADR->execute($address, $subdomain_r[3], $time, $subdomain_r[0]);
        } elsif ($rec_type eq "AAAA") {
            $DDNS_DB_UPD_ADR->execute($subdomain_r[2], $address, $time, $subdomain_r[0]);
        }
        
        my $res = $req->new_response(200, [], "Modfication successful.\n"); return $res->finalize;
    }
}

sub get_help {
    my $req = shift;

    my $c_method = check_method($req);
    if (!defined $c_method) {
        my $c_params = check_params($req, ("key")); 
        if (!defined $c_params && $req->body_parameters->get("key") eq $admin_key) {
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

sub update_ddns {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }
    my $c_key = check_key($req, $subdomain_r[1]); if (defined $c_key) { return $c_key; }
    
    my $subdomain = $req->body_parameters->get('subdomain');
    my $address   = $req->address;
    my $ttl       = 2;
    my $rec_type  = ip_record_type($address);

    if ($subdomain_r[4] == 1) {
        my $res = $req->new_response(401, [], 
        "The subdomain cannot be updated because it is currently locked.\n" .
            "Please contact the administrator for assistance.\n"); 
        return $res->finalize;
    }

    my $dns_update = new Net::DNS::Update($NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->push(update => rr_add("$subdomain.$NAMESERVER_DNS_ZONE. $ttl $rec_type $address"));
    $dns_update->sign_tsig($NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
        my $res = $req->new_response(400, [], "Update failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        if ($rec_type eq "A") {
            $DDNS_DB_UPD_ADR->execute($address, $subdomain_r[3], $time, $subdomain_r[0]);
        } elsif ($rec_type eq "AAAA") {
            $DDNS_DB_UPD_ADR->execute($subdomain_r[2], $address, $time, $subdomain_r[0]);
        }
        
        my $res = $req->new_response(200, [], "Update successful.\n"); return $res->finalize;
    }
}

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

    if ($subdomain_r[3] == 1) {
        my $res = $req->new_response(401, [], 
            "The subdomain cannot be cleared because it is currently locked.\n" .
            "Please contact the administrator for assistance.\n"); 
        return $res->finalize;
    }

    my $dns_update = new Net::DNS::Update($NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->sign_tsig($NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
   	my $res = $req->new_response(400, [], 
       "An attempt to clear $subdomain.$NAMESERVER_DNS_ZONE failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        $DDNS_DB_UPD_ADR->execute("(unset)", "(unset)", $time, $subdomain_r[0]);
        my $res = $req->new_response(200, [], 
            "Successfully cleared $subdomain.$NAMESERVER_DNS_ZONE.\n"); return $res->finalize;
    }
}

sub execute_ddns {
    my $dns_update = shift;
    
    my $dns_resolv = new Net::DNS::Resolver;
    $dns_resolv->nameserver($NAMESERVER); # convert to list later

    my $reply = $dns_resolv->send($dns_update);
    if ($reply) {
        if ($reply->header->rcode eq 'NOERROR') {
            return (1, "");
        } else {
            return (0, $reply->header->r_code);
        }
    } else {
        return (0, $dns_resolv->errorstring);
    }
}

my $app_or_middleware = sub {
    my $env = shift; # PSGI env

    my $req = Plack::Request->new($env);

    my $path_info = $req->path_info;
    my $query     = $req->body_parameters;

    #my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    #my $c_params = check_params($req); if (defined $c_params) { return $c_params; }
    
    if (defined $routes{$path_info}) {
        return $routes{$path_info}($req);
    } else {
        my $res = $req->new_response(404, [], "Invalid URL.\n" .
            "For a full reference view /help or refer to the documentation.\n");
        return $res->finalize;
    }
};

