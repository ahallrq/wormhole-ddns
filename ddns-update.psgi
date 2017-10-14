#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper qw(Dumper);
$Data::Dumper::Sortkeys = 1;

use lib '.';
use conf;
use checks qw(check_params check_key check_method subdomain_exists valid_subdomain);
use util qw(rand_pass ip_record_type);
use database;
use routes::createsub;
#use routes::modifysub;
use routes::deletesub;
#use routes::locksub;
#use routes::chgkey;
use routes::listsub;
use routes::help;
#use routes::updatesub;
#use routes::clearsub;

use DBI;
use Plack::Request;

database::prepare_database();

my %routes = (
    "/create" => \&createsub::create_subdomain,
    "/modify" => \&modify_subdomain,
    "/delete" => \&deletesub::delete_subdomain,
    "/lock" => \&lock_subdomain,
    "/chgkey" => \&chgkey_subdomain,
    "/list" => \&listsub::list_subdomains,
    "/help" => \&help::get_help,
    "/update" => \&update_ddns,
    "/clear" => \&clear_ddns,
);



sub lock_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain", "state")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $conf::admin_key); if (defined $c_key) { return $c_key; }
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

    my $s_res = $database::DDNS_DB_UPD_LCK->execute($lock_state, $subdomain);

    if (defined $s_res) {
        my $res = $req->new_response(200, [], 
            "Successfully $states[$lock_state]ed subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    } else {
        my $res = $req->new_response(400, [], 
            "Failed to $states[$lock_state] subdomain \"$subdomain.$conf::NAMESERVER_DNS_ZONE\"\n");
        return $res->finalize;
    }
}

sub chgkey_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain")); if (defined $c_params) { return $c_params; }
    my $c_key = check_key($req, $conf::admin_key); if (defined $c_key) { return $c_key; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }

    my $subdomain = $req->body_parameters->get("subdomain");

    my $subdomain_key = rand_pass(64);

    my $s_res = $database::DDNS_DB_UPD_KEY->execute($subdomain_key, $subdomain);

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

sub modify_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain", "ip")); if (defined $c_params) { return $c_params; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }
    my $c_key = check_key($req, $conf::admin_key); if (defined $c_key) { return $c_key; }
    
    my $subdomain = $req->body_parameters->get('subdomain');
    my $address   = $req->body_parameters->get('ip');
    my $ttl       = 2;
    my $rec_type  = ip_record_type($address);
    if (!defined $rec_type) {
        my $res = $req->new_response(400, [], "Invalid IP address specified.\n"); return $res->finalize;
    }

    my $dns_update = new Net::DNS::Update($conf::NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$conf::NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->push(update => rr_add("$subdomain.$conf::NAMESERVER_DNS_ZONE. $ttl $rec_type $address"));
    $dns_update->sign_tsig($conf::NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
        my $res = $req->new_response(400, [], "Modfication failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        if ($rec_type eq "A") {
            $database::DDNS_DB_UPD_ADR->execute($address, $subdomain_r[3], $time, $subdomain_r[0]);
        } elsif ($rec_type eq "AAAA") {
            $database::DDNS_DB_UPD_ADR->execute($subdomain_r[2], $address, $time, $subdomain_r[0]);
        }
        
        my $res = $req->new_response(200, [], "Modfication successful.\n"); return $res->finalize;
    }
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

    my $dns_update = new Net::DNS::Update($conf::NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$conf::NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->push(update => rr_add("$subdomain.$conf::NAMESERVER_DNS_ZONE. $ttl $rec_type $address"));
    $dns_update->sign_tsig($conf::NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
        my $res = $req->new_response(400, [], "Update failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        if ($rec_type eq "A") {
            $database::DDNS_DB_UPD_ADR->execute($address, $subdomain_r[3], $time, $subdomain_r[0]);
        } elsif ($rec_type eq "AAAA") {
            $database::DDNS_DB_UPD_ADR->execute($subdomain_r[2], $address, $time, $subdomain_r[0]);
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

    if ($subdomain_r[4] == 1) {
        my $res = $req->new_response(401, [], 
            "The subdomain cannot be cleared because it is currently locked.\n" .
            "Please contact the administrator for assistance.\n"); 
        return $res->finalize;
    }

    my $dns_update = new Net::DNS::Update($conf::NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$conf::NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->sign_tsig($conf::NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
   	my $res = $req->new_response(400, [], 
       "An attempt to clear $subdomain.$conf::NAMESERVER_DNS_ZONE failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        $database::DDNS_DB_UPD_ADR->execute("(unset)", "(unset)", $time, $subdomain_r[0]);
        my $res = $req->new_response(200, [], 
            "Successfully cleared $subdomain.$conf::NAMESERVER_DNS_ZONE.\n"); return $res->finalize;
    }
}

my $app_or_middleware = sub {
    my $env = shift; # PSGI env

    my $req = Plack::Request->new($env);

    my $path_info = $req->path_info;
    my $query     = $req->body_parameters;
    
    if (defined $routes{$path_info}) {
        return $routes{$path_info}($req);
    } else {
        my $res = $req->new_response(404, [], "Invalid URL.\n" .
            "For a full reference view /help or refer to the documentation.\n");
        return $res->finalize;
    }
};


