package database;
use strict;
use warnings;
use DBI;

our ($DDNS_DB_INS, $DDNS_DB_SEL_ALL, $DDNS_DB_SEL, $DDNS_DB_UPD_ADR);
our ($DDNS_DB_DEL, $DDNS_DB_UPD_ATT, $DDNS_DB_UPD_KEY, $DDNS_DB_UPD_LCK);
my $DDNS_DB = DBI->connect("dbi:SQLite:ddns.db","","") or die "Could not connect to database\n";
print("Connected to database.\n");

# This needs to be improved later.

sub prepare_database
{
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

    print("Successfully prepared database.\n");
}

1;