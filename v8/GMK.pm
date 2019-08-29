package GMK;
use Exporter 'import';
our @EXPORT = qw( add_gmk remove_gmk add_same_gmk );

=head1

  This package nicely formats and unformats number by adding G, M and
  K at the end (and dividing accordinly by 1000000000, 1000000 or 1000).

=cut


# Remove G/M/K from the end of a number.
sub remove_gmk {
  no warnings 'numeric';
  my $val = shift;
  return $val * 1_000_000_000 if $val =~ /G/;
  return $val * 1_000_000     if $val =~ /M/;
  return $val * 1_000         if $val =~ /K/;
  return $val;
}

# Add G/M/K at the end of a number.
sub add_gmk {
  my $val = shift;
  return sprintf "%.2fG", $val / 1_000_000_000 if $val > 1_000_000_000;
  return sprintf "%.2fM", $val / 1_000_000     if $val > 1_000_000;
  return sprintf "%.2fK", $val / 1_000         if $val > 1_000;
  return sprintf "%.2f", $val;
}

# Add GMK of first value, same adds the same one on next values.
sub add_same_gmk {
  return map { sprintf "%.2fG", $_ / 1_000_000_000 } @_ if $_[0] > 1_000_000_000;
  return map { sprintf "%.2fM", $_ / 1_000_000 }     @_ if $_[0] > 1_000_000;
  return map { sprintf "%.2fK", $_ / 1_000 }         @_ if $_[0] > 1_000;
  return map { sprintf "%.2f" , $_ }                 @_;
}

1;
