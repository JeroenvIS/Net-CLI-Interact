#!/usr/bin/perl

use strict; use warnings FATAL => 'all';
use Test::More 0.88;

use lib 't/lib';
use Net::CLI::Interact;

my $s = new_ok('Net::CLI::Interact' => [{
    transport => 'Test',
    personality => 'testing',
    add_library => 't/phrasebook',
}]);

$s->set_prompt('TEST_PROMPT');

my $out = $s->cmd('TEST COMMAND');
like($out, qr/^\d{10}$/, 'sent data and command response issued');

ok($s->transport->disconnect, 'transport reinitialized');

my $out2 = $s->cmd('TEST COMMAND');
like($out2, qr/^\d{10}$/, 'more sent data and command response issued');

done_testing;