#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Bot::BasicBot::Pluggable::Module::Trivia' ) || print "Bail out!
";
}

diag( "Testing Bot::BasicBot::Pluggable::Module::Trivia $Bot::BasicBot::Pluggable::Module::Trivia::VERSION, Perl $], $^X" );
