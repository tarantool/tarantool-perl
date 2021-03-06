use utf8;
use strict;
use warnings;

package DR::Tarantool::Constants;
use Carp;

my %ERROR_CODES = ( # from tarantool sources https://github.com/tarantool/tarantool/
    0 => "ER_UNKNOWN",
    1 => "ER_ILLEGAL_PARAMS",
    2 => "ER_MEMORY_ISSUE",
    3 => "ER_TUPLE_FOUND",
    4 => "ER_TUPLE_NOT_FOUND",
    5 => "ER_UNSUPPORTED",
    6 => "ER_NONMASTER",
    7 => "ER_READONLY",
    8 => "ER_INJECTION",
    9 => "ER_CREATE_SPACE",
   10 => "ER_SPACE_EXISTS",
   11 => "ER_DROP_SPACE",
   12 => "ER_ALTER_SPACE",
   13 => "ER_INDEX_TYPE",
   14 => "ER_MODIFY_INDEX",
   15 => "ER_LAST_DROP",
   16 => "ER_TUPLE_FORMAT_LIMIT",
   17 => "ER_DROP_PRIMARY_KEY",
   18 => "ER_KEY_PART_TYPE",
   19 => "ER_EXACT_MATCH",
   20 => "ER_INVALID_MSGPACK",
   21 => "ER_PROC_RET",
   22 => "ER_TUPLE_NOT_ARRAY",
   23 => "ER_FIELD_TYPE",
   24 => "ER_FIELD_TYPE_MISMATCH",
   25 => "ER_SPLICE",
   26 => "ER_ARG_TYPE",
   27 => "ER_TUPLE_IS_TOO_LONG",
   28 => "ER_UNKNOWN_UPDATE_OP",
   29 => "ER_UPDATE_FIELD",
   30 => "ER_FIBER_STACK",
   31 => "ER_KEY_PART_COUNT",
   32 => "ER_PROC_LUA",
   33 => "ER_NO_SUCH_PROC",
   34 => "ER_NO_SUCH_TRIGGER",
   35 => "ER_NO_SUCH_INDEX",
   36 => "ER_NO_SUCH_SPACE",
   37 => "ER_NO_SUCH_FIELD",
   38 => "ER_SPACE_FIELD_COUNT",
   39 => "ER_INDEX_FIELD_COUNT",
   40 => "ER_WAL_IO",
   41 => "ER_MORE_THAN_ONE_TUPLE",
   42 => "ER_ACCESS_DENIED",
   43 => "ER_CREATE_USER",
   44 => "ER_DROP_USER",
   45 => "ER_NO_SUCH_USER",
   46 => "ER_USER_EXISTS",
   47 => "ER_PASSWORD_MISMATCH",
   48 => "ER_UNKNOWN_REQUEST_TYPE",
   49 => "ER_UNKNOWN_SCHEMA_OBJECT",
   50 => "ER_CREATE_FUNCTION",
   51 => "ER_NO_SUCH_FUNCTION",
   52 => "ER_FUNCTION_EXISTS",
   53 => "ER_FUNCTION_ACCESS_DENIED",
   54 => "ER_FUNCTION_MAX",
   55 => "ER_SPACE_ACCESS_DENIED",
   56 => "ER_USER_MAX",
   57 => "ER_NO_SUCH_ENGINE",
   58 => "ER_RELOAD_CFG",
   59 => "ER_CFG",
   60 => "ER_SOPHIA",
   62 => "ER_UNKNOWN_SERVER",
   63 => "ER_CLUSTER_ID_MISMATCH",
   64 => "ER_INVALID_UUID",
   65 => "ER_CLUSTER_ID_IS_RO",
   66 => "ER_RESERVED66",
   67 => "ER_SERVER_ID_IS_RESERVED",
   68 => "ER_INVALID_ORDER",
   69 => "ER_MISSING_REQUEST_FIELD",
   70 => "ER_IDENTIFIER",
   71 => "ER_DROP_FUNCTION",
   72 => "ER_ITERATOR_TYPE",
   73 => "ER_REPLICA_MAX",
   74 => "ER_INVALID_XLOG",
   75 => "ER_INVALID_XLOG_NAME",
   76 => "ER_INVALID_XLOG_ORDER",
   77 => "ER_NO_CONNECTION",
   78 => "ER_TIMEOUT",
   79 => "ER_ACTIVE_TRANSACTION",
   80 => "ER_NO_ACTIVE_TRANSACTION",
   81 => "ER_CROSS_ENGINE_TRANSACTION",
   82 => "ER_NO_SUCH_ROLE",
   83 => "ER_ROLE_EXISTS",
   84 => "ER_CREATE_ROLE",
   85 => "ER_INDEX_EXISTS",
   87 => "ER_ROLE_LOOP",
   88 => "ER_GRANT",
   89 => "ER_PRIV_GRANTED",
   90 => "ER_ROLE_GRANTED",
   91 => "ER_PRIV_NOT_GRANTED",
   92 => "ER_ROLE_NOT_GRANTED",
   93 => "ER_MISSING_SNAPSHOT",
   94 => "ER_CANT_UPDATE_PRIMARY_KEY",
   95 => "ER_UPDATE_INTEGER_OVERFLOW",
   96 => "ER_GUEST_USER_PASSWORD",
   97 => "ER_TRANSACTION_CONFLICT",
   98 => "ER_UNSUPPORTED_ROLE_PRIV",
   99 => "ER_LOAD_FUNCTION",
  100 => "ER_FUNCTION_LANGUAGE",
  101 => "ER_RTREE_RECT",
  102 => "ER_PROC_C",
  103 => "ER_UNKNOWN_RTREE_INDEX_DISTANCE_TYPE",
  104 => "ER_PROTOCOL",
  105 => "ER_UPSERT_UNIQUE_SECONDARY_KEY",
  106 => "ER_WRONG_INDEX_RECORD",
  107 => "ER_WRONG_INDEX_PARTS",
  108 => "ER_WRONG_INDEX_OPTIONS",
  109 => "ER_WRONG_SCHEMA_VERSION",
  110 => "ER_SLAB_ALLOC_MAX",
  111 => "ER_WRONG_SPACE_OPTIONS",
  112 => "ER_UNSUPPORTED_INDEX_FEATURE",
  113 => "ER_VIEW_IS_RO",
);

my %service_spaces_no = (
  _vspace => 281,
  _vindex => 289,
);

sub get_space_no {
    my $space_name = shift;
    return unless exists $service_spaces_no{$space_name};
    return $service_spaces_no{$space_name};
}

sub get_error_name {
    my $error_num  = shift;
    $error_num -= 2 ** 15;

    my $error_name = $ERROR_CODES{$error_num};
    unless ( defined $error_name ) {
        return;
    }
    return $error_name;
}

1;
