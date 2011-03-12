package Net::CLI::Interact::ActionSet;

use Moose;
use Net::CLI::Interact::Action;
with 'Net::CLI::Interact::Role::Iterator';

has default_continuation => (
    is => 'rw',
    isa => 'Net::CLI::Interact::ActionSet',
    required => 0,
);

has current_match => (
    is => 'rw',
    isa => 'RegexpRef',
    required => 0,
);

has '+_sequence' => (
    isa => 'ArrayRef[Net::CLI::Interact::Action]',
);

sub BUILDARGS {
    my ($class, @rest) = @_;
    # accept single hash ref or naked hash
    my $params = (ref $rest[0] eq ref {} and scalar @rest == 1 ? $rest[0] : {@rest});

    if (exists $params->{actions} and ref $params->{actions} eq ref []) {
        foreach my $a (@{$params->{actions}}) {
            if (ref $a eq 'Net::CLI::Interact::ActionSet') {
                push @{$params->{_sequence}}, $a->_sequence;
                next;
            }

            if (ref $a eq 'Net::CLI::Interact::Action') {
                push @{$params->{_sequence}}, $a;
                next;
            }

            if (ref $a eq ref {}) {
                push @{$params->{_sequence}},
                    Net::CLI::Interact::Action->new($a);
                next;
            }

            confess "don't know what to do with a: '$a'\n";
        }
        delete $params->{actions};
    }

    return $params;
}

sub clone {
    my $self = shift;
    return Net::CLI::Interact::ActionSet->new({
        actions => [ map { $_->clone } $self->_sequence ],
        _callbacks => $self->_callbacks,
        ($self->default_continuation
            ? (default_continuation => $self->default_continuation) : ()),
        ($self->current_match ? (current_match => $self->current_match) : ()),
    });
}

# store params to the set, used when send is passed via sprintf
sub apply_params {
    my ($self, @params) = @_;

    $self->reset;
    while ($self->has_next) {
        my $next = $self->next;
        $next->params([splice @params, 0, $next->num_params]);
    }
}

has _callbacks => (
    is => 'rw',
    isa => 'ArrayRef[CodeRef]',
    required => 0,
    default => sub { [] },
);

sub register_callback {
    my $self = shift;
    $self->_callbacks([ @{$self->_callbacks}, shift ]);
}

sub execute {
    my $self = shift;

    $self->_pad_send_with_match;
    $self->_forward_continuation_to_match;
    $self->_do_exec;
    $self->_marshall_responses;
}

sub _do_exec {
    my $self = shift;

    $self->reset;
    while ($self->has_next) {
        $_->($self->next) for @{$self->_callbacks};
    }
}

# pad out the Actions with match Actions if needed between send pairs.
sub _pad_send_with_match {
    my $self = shift;
    my $match = Net::CLI::Interact::Action->new({
        type => 'match', value => $self->current_match,
    });

    $self->reset;
    while ($self->has_next) {
        my $this = $self->next;
        my $next = $self->peek or last; # careful...
        next unless $this->type eq 'send' and $next->type eq 'send';

        $self->insert_at($self->idx + 1, $match->clone);
    }

    # always finish on a match
    if ($self->last->type ne 'match') {
        $self->insert_at($self->count, $match->clone);
    }
}

# carry-forward a continuation beacause it's the match which really does the
# heavy lifting.
sub _forward_continuation_to_match {
    my $self = shift;

    $self->reset;
    while ($self->has_next) {
        my $this = $self->next;
        my $next = $self->peek or last; # careful...
        my $cont = ($this->continuation || $self->default_continuation);
        next unless $this->type eq 'send'
            and $next->type eq 'match'
            and defined $cont;

        $next->continuation($cont);
    }
}

# marshall the responses so as to move data from match to send
sub _marshall_responses {
    my $self = shift;

    $self->reset;
    while ($self->has_next) {
        my $send = $self->next;
        my $match = $self->peek or last; # careful...
        next unless $match->type eq 'match';

        my $response = $match->response; # need an lvalue
        my $cmd = $send->value;
        $response =~ s/^$cmd\s+//;

        if ($response =~ s/(\s+)(\S+)\s*$/$1/) {
            $match->response($2);
            $send->response($response);
        }
    }
}

1;
