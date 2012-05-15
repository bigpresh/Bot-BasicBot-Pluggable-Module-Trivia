package Bot::BasicBot::Pluggable::Module::Trivia;

use warnings;
use strict;

=head1 NAME

Bot::BasicBot::Pluggable::Module::Trivia - Trivia quiz for Bot::BasicBot::Pluggabble powered bots


=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Load the module as per any other bot module.


=head1 CONFIGURATION

TODO: implement a config setting to determine which channels the bot is allowed
to run the trivia in.  Currently, any channel can have a trivia game.


=head1 IRC USAGE

The bot responds to certain in-channel commands:

=over

=item C<!trivia>

Starts a trivia quiz in this channel

=back

When a game is in progress, the first person to say the answer (as a normal
channel message) is awarded the points.

=cut


my %games;

sub said {
    my ($self,$mess,$pri) = @_;
    return unless $pri == 2;

    if ($mess->{body} =~ /^!trivia/) {
        if (exists $games{ $mess->{channel} }) {
            return "There's already a game running, silly.";
        }

        # OK, initialise an empty game and ask a question
        $games{ $mess->{channel} } = {
            channel => $mess->{channel},
            status  => 'noquestion'
        };
        return "OK, let's play us some trivia - stand by!";
        return $self->format_msg('started', $mess);
    }

    # If there's a game in progress, this could be someone guessing an answer -
    # let's see if that's the case
    my $game = $games{ $mess->{channel} };
    return unless $game && $game->{status} eq 'waiting';

    my $answer = $game->{answer};
    my $guess  = lc $mess->{body};
    $guess =~ s/^\s+|\s+$//g;

    my $correct_guess;
    if ($answer =~ m{^/}) {
        # Answers starting with / are presumed to be a regex
        # TODO: match it, safely
    } elsif ($guess eq lc $answer) {
        $correct_guess++;
    }

    if ($correct_guess) {
        return $self->correct_guess($game, $mess);
    }

}

sub correct_guess {
    my ($self, $game, $mess) = @_;

    
    # TODO: update this user's score


    $game->{status} = 'noquestion';
    
    return $self->format_response('correct', $mess,
        { 
            question => $game->{current_question}{question}, 
            answer   => $game->{current_question}{answer},
            winner   => $mess->{who},
            newscore => 42, # FIXME
        }
    );

}


# TODO: this needs to be able to read custom messages from config for
# customisability.
# Should always be given the message hashref, and for some messages, also an
# additional hashref of info.  The keys from both will be merged and made
# available to the message template.
sub format_response {
    my ($self, $response_name, $mess, $params) = @_;

    my %responses = (
        started  => 'OK, trivia game will start in a moment...',
        newquestion => 'Question %id% : %question%',
        hint => "Question %id% : %question%\nHint %hintnum% : %hint%",
        congrats => 'Congratulations %who%, the answer was indeed %answer%!'
                  . ' You now have %newscore% points.',
        questiontimeout => 'Bad luck, nobody got it!  It was %answer%',
    );
    my $response = $responses{$response_name}
        or return "ERROR: unknown response name $response_name requested!";
    
    $params->{$_} = $mess->{$_} for keys %$mess;
    $response =~ s/%([^%]+)%/$params->{$1}/ge;
    return $response;
}


sub tick {
    my $self = shift;

    # Look for games where we need to change state (ask a question, show a hint,
    # or time out the question)
    game:
    for my $game (values %games) {
        my $timeout = $self->timeout_for_status($game->{status});
        next game if time - $game->{last_action} >= $timeout;
        
        # Map current state to method to call to progress
        my $action = {
            noquestion => 'ask_question',
            waiting    => 'hint_or_timeout',
        }->{ $game->{status} };
        $self->$action($game);
    }
}


sub ask_question {
    my ($self, $game) = @_;

    my $question = $self->pick_question;

    $game->{current_question} = $question;
    $game->{state} = 'waiting';
    $self->say(
        channel => $game->{channel},
        body => $self->format_response(
            'newquestion', {}, {
                id       => $question->{id},
                question => $question->{question},
            },
        ),
    );
}

sub hint_or_timeout {
    my ($self, $game) = @_;

    # If we can give another hint, do so
    if ($game->{current_question}{hints} < 3) {
        my $new_hint = $self->update_hint($game->{current_question});
        $self->say(
            channel => $game->{channel},
            body    => $self->format_response('newhint', {},
                {
                    question => $game->{current_question}{question},
                    hint     => $game->{current_question}{hint},
                    hintnum  => $game->{current_question}{hints},
                }
            ),
        );
    } else {
        # OK, no more hints allowed, timeout
        $game->{status} = 'noquestion';
        # TODO: maybe record that this question was used & not guessed?

        $self->say(
            channel => $game->{channel},
            body    => $self->format_response('questiontimeout', {},
                { 
                    map { 
                    $_ => $game->{current_question}{$_} 
                    } qw(id question answer) 
                },
            ),
        );
        delete $game->{question};
    }
}

        

# Given a question, update the hint in it (pick a character at random and change
# it from a question mark to the actual character)
sub update_hint {
    my ($self, $question) = @_;

    # First, make sure the hint is initialised
    if (!exists $question->{hint}) {
        $question->{hint} = $question->{answer};
        $question->{hint} =~ s/\w/?/g;
    }
    my @hintchars = split //, $question->{hint};
    while (grep { $_ eq '?' } @hintchars) {
        my $charpos = rand length $question->{hint};
        next if $hintchars[$charpos] eq '?';

        $hintchars[$charpos] = (split //, $question->{question})[$charpos];
    }
    $question->{hints}++;
    return $question->{hint} = join '', @hintchars;
}


# Pick a question.
# TODO: actually pick one from a database.
sub pick_question {
    my ($self) = @_;

    # FIXME: implement.
    return {
        id => 42,
        question => "Who wrote this?",
        answer => "Dave",
    };
}

            

# Decide how long we should wait in the given state.  Allows e.g. the delay
# between hints to be different to e.g. the delay between a question being
# answered/timing out and a new question asked.
sub timeout_for_status {
    my ($self, $state) = @_;

    # TODO: do something more intelligent here
    return 3;
}



=head1 AUTHOR

David Precious, C<< <davidp at preshweb.co.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-bot-basicbot-pluggable-module-trivia at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Bot-BasicBot-Pluggable-Module-Trivia>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Bot::BasicBot::Pluggable::Module::Trivia


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Bot-BasicBot-Pluggable-Module-Trivia>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Bot-BasicBot-Pluggable-Module-Trivia>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Bot-BasicBot-Pluggable-Module-Trivia>

=item * Search CPAN

L<http://search.cpan.org/dist/Bot-BasicBot-Pluggable-Module-Trivia/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Bot::BasicBot::Pluggable::Module::Trivia
