package Net::CLI::Interact::Role::Engine;

use Moose::Role;
use Net::CLI::Interact::Action;
use Net::CLI::Interact::ActionSet;

has '_prompt' => (
    is => 'rw',
    isa => 'Maybe[RegexpRef]',
    required => 0,
    reader => 'prompt',
    clearer => 'unset_prompt',
    trigger => sub {
        (shift)->log('prompt', 'info', 'prompt has been set to', (shift));
    },
);

sub set_prompt {
    my ($self, $prompt) = @_;
    $self->_prompt( $self->_prompt_tbl->{$prompt}->first->value );
}

has 'last_actionset' => (
    is => 'rw',
    isa => 'Net::CLI::Interact::ActionSet',
    required => 0,
);

sub last_response {
    my $self = shift;
    return $self->last_actionset->item_at(-2)->response;
}

sub last_prompt {
    my $self = shift;
    return $self->last_actionset->item_at(-1)->response;
}

sub last_prompt_as_match {
    my $prompt = (shift)->last_prompt;
    return qr/^$prompt$/;
}

sub macro {
    my ($self, $name, @params) = @_;
    $self->log('engine', 'notice', 'running macro', $name);
    $self->log('engine', 'info', 'macro params are:', join ', ', @params);

    my $set = $self->_macro_tbl->{$name}->clone;
    $set->apply_params(@params);
    $self->_execute_actions($set);
}

sub cmd {
    my ($self, $command) = @_;
    $self->log('engine', 'notice', 'running command', $command);

    $self->_execute_actions(
        Net::CLI::Interact::Action->new({
            type => 'send',
            value => $command,
        }),
    );
}

sub _execute_actions {
    my $self = shift;
    $self->log('engine', 'notice', 'executing actions');

    my $set = Net::CLI::Interact::ActionSet->new({ actions => [@_] });
    $set->register_callback(sub { $self->do_action(@_) });

    # user can install a prompt, call find_prompt, or let us trigger that
    $self->find_prompt if not $self->last_actionset;

    $self->log('engine', 'debug', 'dispaching to set execute method');
    $set->execute($self->prompt || $self->last_prompt_as_match);
    $self->last_actionset($set);

    # if user used a match ref then we assume new prompt value
    if ($self->last_actionset->last->is_lazy) {
        $self->log('prompt', 'info', 'last match was a prompt reference, setting new prompt');
        $self->_prompt($self->last_actionset->last->value);
    }
}

# pump until any of the prompts matches the output buffer
sub find_prompt {
    my $self = shift;
    $self->log('prompt', 'notice', 'finding prompt');

    while ($self->_harness->pump) {
        foreach my $prompt (keys %{ $self->_prompt_tbl }) {
            # prompts consist of only one match action
            if ($self->out =~ $self->_prompt_tbl->{$prompt}->first->value) {
                $self->log('prompt', 'info', "hit, matches prompt $prompt");
                $self->last_actionset(
                    Net::CLI::Interact::ActionSet->new({ actions => [
                        $self->_prompt_tbl->{$prompt}->first->clone({
                            response => $self->flush,
                        })
                    ] })
                );
                return;
            }
            $self->log('prompt', 'debug', "nope, doesn't (yet) match $prompt");
        }
    }
}

1;
