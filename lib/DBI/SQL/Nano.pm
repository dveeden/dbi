package DBI::SQL::Nano;

use strict;
use warnings;
use vars qw( $VERSION $versions );

BEGIN {
    $VERSION = '0.01';
    $versions->{nano_version} = $VERSION;
    eval { require "SQL/Statement.pm" } unless $ENV{DBI_SQL_NANO};
    if ($@ or $ENV{DBI_SQL_NANO}) {
        @DBI::SQL::Nano::Statement::ISA = qw(DBI::SQL::Nano::Statement_);
        @DBI::SQL::Nano::Table::ISA     = qw(DBI::SQL::Nano::Table_);
    }
    else {
        @DBI::SQL::Nano::Statement::ISA = qw(SQL::Statement);
        @DBI::SQL::Nano::Table::ISA     = qw(SQL::Eval::Table);
        $versions->{statement_version}  = $SQL::Statement::VERSION;
    }
}

package DBI::SQL::Nano::Statement_;
use vars qw($numexp);
# XXX change to DBI::looks_like_number?
$numexp= qr/^([+-]?|\s+)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/;
sub new {
    my($class,$sql) = @_;
    my $self  = {};
    bless $self, $class;
    return $self->prepare($sql);
}

#####################################################################
# PREPARE
#####################################################################
sub prepare {
    my($self,$sql) = @_;
    for ($sql) {
        /^\s*CREATE\s+TABLE\s+(.*?)\s*\((.+)\)\s*$/is
            &&do{
                $self->{command}      = 'CREATE';
                $self->{table_name}   = $1;
                $self->{column_names} = parse_comma_list($2) if $2;
            };
        /^\s*DROP\s+TABLE\s+(.*?)\s*$/is
            &&do{
                $self->{command}      = 'DROP';
                $self->{table_name}   = $1;
            };
        /^\s*SELECT\s+(.*?)\s+FROM\s+(\w+)(\s+WHERE\s+(.*))?/is
            &&do{
                $self->{command}      = 'SELECT';
                $self->{column_names} = parse_comma_list($1) if $1;
                $self->{table_name}   = $2;
                $self->{where_clause} = $self->parse_where_clause($4) if $4;
            };
        /^\s*INSERT\s+INTO\s+(\w+)\s*(\((.*?)\))?\s*VALUES\s*\((.+)\)/is
            &&do{
                $self->{command}      = 'INSERT';
                $self->{table_name}   = $1;
                $self->{column_names} = parse_comma_list($2) if $2;
                $self->{values}       = $self->parse_values_list($4) if $4;
            };
        /DELETE\s+FROM\s+(\w+)(\s+WHERE\s+(.*))?/is
            &&do{
                $self->{command}      = 'DELETE';
                $self->{table_name}   = $1;
                $self->{where_clause} = $self->parse_where_clause($3) if $3;
            };
        /UPDATE\s+(\w+)\s+SET\s+(.+)WHERE\s+(.+)/is
            &&do{
                $self->{command}      = 'UPDATE';
                $self->{table_name}   = $1;
                $self->parse_set_clause($2) if $2;
                $self->{where_clause} = $self->parse_where_clause($3) if $3;
            };
    }
    return undef unless $self->{command} and $self->{table_name};
    $self->{NAME} = $self->{column_names};
    return $self;
}
sub parse_comma_list  {[map{clean_parse_str($_)} split(',',shift)]}
sub clean_parse_str {
    $_ = shift; s/\(//;s/\)//;s/^\s+//; s/\s+$//; s/^(\S+)\s*.*/$1/; $_;
}
sub parse_values_list {
    my($self,$str) = @_;
    [map{$self->parse_value(clean_parse_str($_))}split(',',$str)]
}
sub parse_set_clause {
    my $self = shift;
    my @cols = split /,/, shift;
    my $set_clause;
    for my $col(@cols) {
        my($col_name,$value)= $col =~ /^\s*(.+?)\s*=\s*(.+?)\s*$/s;
        push @{$self->{column_names}}, $col_name;
        push @{$self->{values}}, $self->parse_value($value);
    }
}
sub parse_value {
    my($self,$str) = @_;
    if ($str =~ /^\?$/) {
        push @{$self->{params}},'?';
        return { value=>'?'  ,type=> 'placeholder' };
    }
    return { value=>undef,type=> 'NULL'        } if $str =~ /^NULL$/i;
    return { value=>$1   ,type=> 'string'      } if $str =~ /^'(.+)'$/s;
    return { value=>$str ,type=> 'number'      } if $str =~ $numexp;
    return { value=>$str ,type=> 'column'      };
}
sub parse_where_clause {
    my($self,$str) = @_;
    $str =~ s/\s+$//;
    my($neg) = $str =~ s/^\s*(NOT)\s+//is;
    my $opexp = '=|<>|<=|>=|<|>|LIKE|CLIKE|IS';
    my($val1,$op,$val2) = $str =~ /(\S+?)\s*($opexp)\s*(\S+)/is;
    #die "<$val1> <$op> <$val2>";
    return {
        arg1 => $self->parse_value($val1),
        arg2 => $self->parse_value($val2),
        op   => $op,
        neg  => $neg,
    }
}
#####################################################################
# EXECUTE
#####################################################################
sub execute {
    my($self, $data, $params) = @_;
    my $num_placeholders = $self->params;
    my $num_params       = scalar @$params || 0;
    die "Number of params '$num_params' does not match "
      . "number of placeholders '$num_placeholders'!\n"
      unless $num_placeholders == $num_params;
    if (scalar @$params) {
        for my $i(0..$#{$self->{values}}) {
            if ($self->{values}->[$i]->{type} eq 'placeholder') {
                $self->{values}->[$i]->{value} = shift @$params;
            }
        }
        if ($self->{where_clause}) {
            if ($self->{where_clause}->{arg1}->{type} eq 'placeholder') {
                $self->{where_clause}->{arg1}->{value} = shift @$params;
            }
            if ($self->{where_clause}->{arg2}->{type} eq 'placeholder') {
                $self->{where_clause}->{arg2}->{value} = shift @$params;
            }
        }
    }
    my $command = $self->{command};
    ( $self->{'NUM_OF_ROWS'},
      $self->{'NUM_OF_FIELDS'},
      $self->{'data'},
    ) = $self->$command($data, $params);
    $self->{'NUM_OF_ROWS'} || '0E0';
}
sub DROP ($$$) {
    my($self, $data, $params) = @_;
    my $tbl_obj = { file => $self->{table_name} };
    my $class = ref($self);
    $class =~ s/::Statement/::Table/;
    bless($tbl_obj, $class);
    $self->{tbl_obj} = $tbl_obj;
    eval { $tbl_obj->drop($data); };
    (-1, 0);
}
sub CREATE ($$$) {
    my($self, $data, $params) = @_;
     my $table = $self->open_tables($data, 1, 1);
    $table->push_names($data, $self->{column_names});
    (0, 0);
}
sub INSERT ($$$) {
    my($self, $data, $params) = @_;
     my $table = $self->open_tables($data, 0, 1);
    $table->seek($data, 0, 2);
    my($array) = [];
    my($val, $col, $i);
    $self->{column_names}=$table->{col_names} unless $self->{column_names};
    my $cNum = scalar(@{$self->{column_names}}) if $self->{column_names};
    my $param_num = 0;
    if ($cNum) {
        for ($i = 0;  $i < $cNum;  $i++) {
            $col = $self->{column_names}->[$i];
            $array->[$self->column_nums($table,$col)] = $self->row_values($i);
        }
    } else {
        die "Bad col names in INSERT";
    }
    $table->push_row($data, $array);
    (1, 0);
}
sub DELETE ($$$) {
    my($self, $data, $params) = @_;
    my $table = $self->open_tables($data, 0, 1);
    my($affected) = 0;
    my(@rows, $array);
    if ( $table->can('delete_one_row') ) {
        while (my $array = $table->fetch_row($data)) {
            if ($self->eval_where($table,$array)) {
                ++$affected;
                $table->delete_one_row($data,$array);
	      }
        }
        return ($affected, 0);
    }
    while ($array = $table->fetch_row($data)) {
        if ($self->eval_where($table,$array)) {
            ++$affected;
        } else {
            push(@rows, $array);
        }
    }
    $table->seek($data, 0, 0);
    foreach $array (@rows) {
        $table->push_row($data, $array);
    }
    $table->truncate($data);
    return ($affected, 0);
}
sub SELECT ($$$) {
    my($self, $data, $params) = @_;
     my $table = $self->open_tables($data, 0, 0);
    my $tname = $self->{table_name};
    my($affected) = 0;
    my(@rows, $array, $val, $col, $i);
    while ($array = $table->fetch_row($data)) {
        if ($self->eval_where($table,$array)) {
 	    if ( $self->{fetched_from_key} ) {
                push(@rows, [$self->{fetched_value}] );
                return (scalar(@rows),scalar @{$self->{column_names}},\@rows);
	    }
            my $col_nums = $self->column_nums($table);
            my %cols   = reverse %{ $col_nums };
            my $rowhash;
            for (sort keys %cols) {
                $rowhash->{$cols{$_}} = $array->[$_];
            }
            my @newarray;
            for ($i = 0;  $i < @{$self->{column_names}};  $i++) {
               $col = $self->{column_names}->[$i];
               push @newarray,$rowhash->{$col};
            }
            push(@rows, \@newarray);
        }
    }
    (scalar(@rows), scalar @{$self->{column_names}}, \@rows);
}
sub UPDATE ($$$) {
    my($self, $data, $params) = @_;
    my $table = $self->open_tables($data, 0, 1);
    my($eval,$all_cols) = $self->open_tables($data, 0, 1);
    return undef unless $eval;
    my($affected) = 0;
    my(@rows, $array, $val, $col, $i);
    while ($array = $table->fetch_row($data)) {
        if ($self->eval_where($table,$array)) {
            my $col_nums = $self->column_nums($table);
            my %cols   = reverse %{ $col_nums };
            my $rowhash;
            for (sort keys %cols) {
                $rowhash->{$cols{$_}} = $array->[$_];
            }
            for ($i = 0;  $i < @{$self->{column_names}};  $i++) {
               $col = $self->{column_names}->[$i];
               $array->[$self->column_nums($table,$col)]=$self->row_values($i);
            }
            $affected++;
            push(@rows, $array);
	}
        else {
            push(@rows, $array);
        }
    }
    $table->seek($data, 0, 0);
    foreach my $array (@rows) {
        $table->push_row($data, $array);
    }
    $table->truncate($data);
    ($affected, 0);
}
sub column_nums {
    my($self,$table,$stmt_col_name)=@_;
    my %dbd_nums = %{ $table->{col_nums} };
    my @dbd_cols = @{ $table->{col_names} };
    my %stmt_nums;
    if ($stmt_col_name) {
        while(my($k,$v)=each %dbd_nums) {
            return $v if uc $k eq uc $stmt_col_name;
        }
        return undef;
    }
    for my $i(0 .. $#dbd_cols) {
        for my $stmt_col(@{$self->{column_names}}) {
            $stmt_nums{$stmt_col} = $i if uc $dbd_cols[$i] eq uc $stmt_col;
        }
    }
    return \%stmt_nums;
}
sub eval_where {
    my $self   = shift;
    my $table  = shift;
    my $rowary = shift;
    my $where = $self->{"where_clause"} || return 1;
    my $col_nums = $table->{"col_nums"} ;
    my %cols   = reverse %{ $col_nums };
    my $rowhash;
    for (sort keys %cols) {
        $rowhash->{uc $cols{$_}} = $rowary->[$_];
    }
    return $self->process_predicate ($where,$table,$rowhash);
}
sub process_predicate {
    my($self,$pred,$table,$rowhash) = @_;
    my $val1 = $pred->{arg1};
    if ($val1->{type} eq 'column') {
        $val1 = $rowhash->{ uc $val1->{value}};
    }
    else {
        $val1 = $val1->{value};
    }
    my $val2 = $pred->{arg2};
    if ($val2->{type}eq 'column') {
        $val2 = $rowhash->{uc $val2->{value}};
    }
    else {
        $val2 = $val2->{value};
    }
    my $op   = $pred->{op};
    my $neg  = $pred->{neg};
    my $match;
    if ( $self->{command} eq 'SELECT'
         and $op eq '=' and !$neg and $table->can('fetch_one_row')
       ) {
        my $key_col = $table->fetch_one_row(1,1);
        if ($pred->{arg1}->{value} =~ /^$key_col$/i) {
            $self->{fetched_from_key}=1;
            $self->{fetched_value} = $table->fetch_one_row(
                0,$pred->{arg2}->{value}
            );
            return 1;
	}
    }
    $match = $self->is_matched($val1,$op,$val2) || 0;
    if ($neg) { $match = $match ? 0 : 1; }
    return $match;
}
sub is_matched {
    my($self,$val1,$op,$val2)=@_;
    if ($op eq 'IS') {
        return 1 if (!defined $val1 or $val1 eq '');
        return 0;
    }
    #return $val1 == $val2;
    #print "[$val1] [$op] [$val2]\n";
    $val1 = '' unless defined $val1;
    $val2 = '' unless defined $val2;
    if ($op =~ /LIKE|CLIKE/i) {
        $val2 = quotemeta($val2);
        $val2 =~ s/\\%/.*/g;
        $val2 =~ s/_/./g;
    }
    if ($op eq 'LIKE' )  { return $val1 =~ /^$val2$/s;  }
    if ($op eq 'CLIKE' ) { return $val1 =~ /^$val2$/si; }
    if ($val1 =~ /$numexp/ and $val2 =~ /$numexp/) {
        if ($op eq '<'  ) { return $val1 <  $val2; }
        if ($op eq '>'  ) { return $val1 >  $val2; }
        if ($op eq '='  ) { return $val1 == $val2; }
        if ($op eq '<>' ) { return $val1 != $val2; }
        if ($op eq '<=' ) { return $val1 <= $val2; }
        if ($op eq '>=' ) { return $val1 >= $val2; }
    }
    else {
        if ($op eq '<'  ) { return $val1 lt $val2; }
        if ($op eq '>'  ) { return $val1 gt $val2; }
        if ($op eq '='  ) { return $val1 eq $val2; }
        if ($op eq '<>' ) { return $val1 ne $val2; }
        if ($op eq '<=' ) { return $val1 ge $val2; }
        if ($op eq '>=' ) { return $val1 le $val2; }
    }
}
sub params {
    my $self = shift;
    my $val_num = shift;
    if (!$self->{"params"}) { return 0; }
    if (defined $val_num) {
        return $self->{"params"}->[$val_num];
    }
    if (wantarray) {
        return @{$self->{"params"}};
    }
    else {
        return scalar @{ $self->{"params"} };
    }

}
sub open_tables {
    my($self, $data, $createMode, $lockMode) = @_;
    my $table_name = $self->{table_name};
    my $table;
    eval{$table = $self->open_table($data,$table_name,$createMode,$lockMode)};
    die $@ if $@;
    die "Couldn't open table '$table_name'!" unless $table;
    if (!$self->{column_names} or $self->{column_names}->[0] eq '*') {
        $self->{column_names} = $table->{col_names};
    }
    return $table;
}
sub row_values {
    my $self = shift;
    my $val_num = shift;
    if (!$self->{"values"}) { return 0; }
    if (defined $val_num) {
        return $self->{"values"}->[$val_num]->{value};
    }
    if (wantarray) {
        return map{$_->{"value"} } @{$self->{"values"}};
    }
    else {
        return scalar @{ $self->{"values"} };
    }
}
package DBI::SQL::Nano::Table_;
sub new ($$) {
    my($proto, $attr) = @_;
    my($self) = { %$attr };
    bless($self, (ref($proto) || $proto));
    $self;
}
1;
__END__

=pod

=head1 SUPPORTED SQL SYNTAX

  statement ::=
      DROP TABLE <table_name>
    | CREATE TABLE <table_name> <col_def_list>
    | INSERT INTO <table_name> <insert_col_list> VALUES <val_list>
    | DELETE FROM <table_name> <where_clause>
    | UPDATE <table_name> SET <set_clause> <where_clause>
    | SELECT <select_col_list> FROM <table_name> <where_clause>
  identifiers ::=
    * table and column names should be valid SQL identifiers
    * especially avoid using spaces and commas in identifiers
    * note: there is no error checking for invalid names, some
      will be accepted, others will cause parse failures
  table_name ::=
    * only one table (no multiple table operations)
    * see identifier for valid table names
  col_def_list ::=
    * a parens delimited, comma-separated list of column names
    * see identifier for valid column names
    * column types and column constraints may be included but are ignored
      e.g. these are all the same:
        (id,phrase)
        (id INT, phrase VARCHAR(40))
        (id INT PRIMARY KEY, phrase VARCHAR(40) NOT NULL)
  insert_col_list ::=
    * a parens delimited, comma-separated list of column names
    * as in standard SQL, this is optional
  select_col_list ::=
    * a comma-separated list of column names
    * or an asterisk denoting all columns
  val_list ::=
    * a parens delimited, comma-separated list of values which can be:
       * placeholders (an unquoted question mark)
       * numbers (unquoted numbers)
       * column names (unquoted strings)
       * nulls (unquoted word NULL)
       * strings (delimited with single quote marks);
       * note: leading and trailing percent mark (%) and underscore (_)
         can be used as wildcards in quoted strings for use with
         the LIKE and CLIKE operators
       * note: escaped single quote marks within strings are not
         supported, neither are embedded commas, use placeholders instead
  set_clause ::=
    * a comma-separated list of column = value pairs
    * see val_list for acceptable value formats
  where_clause ::=
    * a single "column/value <op> column/value" predicate, optionally
      preceded by "NOT"
    * note: multiple predicates combined with ORs or ANDs are not supported
    * see val_list for acceptable value formats
    * op may be one of:
         < > >= <= = <> LIKE CLIKE IS
    * CLIKE is a case insensitive LIKE

=cut
