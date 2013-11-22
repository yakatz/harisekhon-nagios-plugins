#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-28 00:12:10 +0100 (Sun, 28 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check given HBase table(s) are online via the HBase Stargate Rest API Server

More simplistic than check_hbase_tables.pl program which uses the better programmatic Thrift API and has more levels of checks.

This plugin only checks to see if the given tables have regions listed on the cluster status page of the Stargate. Recommend to use check_hbase_tables.pl instead if possible

Written on CDH 4.3 (HBase 0.94.6-cdh4.3.0), also tested on CDH 4.2.1 and CDH 4.4.0

Known Limitations:

Known Issues/Limitations:

1. The HBase REST API doesn't seem to expose details on -ROOT- and .META. regions so the code only checks they are present (user specified tables are checked for online regions)
2. The HBase REST API doesn't distinguish between disabled and otherwise unavailable/nonexistent tables, instead use the thrift monitoring plugin check_hbase_tables.pl (aka check_hbase_tables_thrift.pl), or as a fallback the check_hbase_tables_jsp.pl for that distinction
3. The HBase REST Server will timeout the request for information if the HBase Master is down, you will see this as \"CRITICAL: '500 read timeout'\"";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;

my $default_port = 20550;
$port = $default_port;

my $tables;

%options = (
    "H|host=s"         => [ \$host,         "HBase Stargate Rest API server address to connect to" ],
    "P|port=s"         => [ \$port,         "HBase Stargate Rest API server port to connect to (defaults to $default_port)" ],
    "T|tables=s"       => [ \$tables,       "Table(s) to check. This should be a list of user tables, not -ROOT- or .META. catalog tables which are checked additionally. If no tables are given then only -ROOT- and .META. are checked" ],
);

@usage_order = qw/host port tables/;
get_options();

$host  = validate_host($host);
$host  = validate_resolvable($host);
$port  = validate_port($port);
my @tables = ( "-ROOT-", ".META.");
push(@tables, split(/\s*,\s*/, $tables)) if defined($tables);
@tables or usage "no valid tables specified";
@tables = uniq_array @tables;
my $table;
foreach $table (@tables){
    if($table =~ /^(-ROOT-|\.META\.)$/){
    } else {
        $table = isDatabaseTableName($table) || usage "invalid table name $table given";
    }
}
vlog_options "tables", "[ " . join(" , ", @tables) . " ]";

my $url = "http://$host:$port/status/cluster";
vlog_options "url", $url;

vlog2;
set_timeout();

$status = "OK";

my $ua_timeout = $timeout - 1;
$ua_timeout = 1 if($ua_timeout < 1);

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname $main::VERSION");
$ua->timeout($ua_timeout);
$ua->show_progress(1) if $debug;

vlog2 "querying Stargate";
my $res = $ua->get($url);
vlog2 "got response";
my $status_line  = $res->status_line;
vlog2 "status line: $status_line";
my $content = $res->content;
vlog3 "\ncontent:\n\n$content\n";
vlog2;

unless($res->code eq 200){
    quit "CRITICAL", "'$status_line'";
}
if($content =~ /\A\s*\Z/){
    quit "CRITICAL", "empty body returned from '$url'";
}

my @tables_online;
my @tables_not_available;
foreach $table (@tables){
    if($content =~ /^ {8}$table,[^,]*,[\w\.]+$/m){
        vlog2 "found table $table";
        push(@tables_online, $table);
    } else {
        vlog2 "table '$table' not found / available in output from Stargate";
        critical;
        push(@tables_not_available, $table);
    }
}
vlog2;

$msg = "HBase ";

sub print_tables($@){
    my $str = shift;
    my @arr = @_;
    if(@arr){
        @arr = uniq_array @arr;
        plural scalar @arr;
        $msg .= "table$plural $str: " . join(" , ", @arr) . " -- ";
    }
}

print_tables("not found/available", @tables_not_available);
print_tables("online",        @tables_online);

$msg =~ s/ -- $//;

quit $status, $msg;
